package main

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"github.com/OwlShack/meshcore-go/hardware"
)

const (
	modemConnectTimeout = 10 * time.Second
	modemTxTimeout      = 12 * time.Second
	modemCmdTimeout     = 3 * time.Second
	modemPingInterval   = 30 * time.Second
)

type arbReqKind int

const (
	reqKindTx arbReqKind = iota
	reqKindHwCmd
	reqKindRawFrame
)

type arbReq struct {
	kind     arbReqKind
	subCmd   byte
	payload  []byte
	rawFrame []byte
	respCh   chan arbResp
}

type arbResp struct {
	subCmd byte
	data   []byte
	err    error
}

type hwFrame struct {
	subCmd byte
	data   []byte
}

// SiteModem manages a persistent KISS-over-TCP connection to a remote ser2net
// modem, arbitrates single-flight TX/HW commands, and serves a local virtual
// KISS TCP listener for OwlShack.
type SiteModem struct {
	id     SiteID
	cfg    SiteConfig
	log    *slog.Logger
	onRxFn func(SiteID, []byte)

	connected  atomic.Bool
	lastPongNs atomic.Int64
	rxPackets  atomic.Uint64
	txPackets  atomic.Uint64
	txErrors   atomic.Uint64

	reqCh chan arbReq

	clientMu               sync.Mutex
	clientConn             net.Conn
	clientWantSignalReport bool
}

func NewSiteModem(id SiteID, cfg SiteConfig, log *slog.Logger, onRxFn func(SiteID, []byte)) *SiteModem {
	if log == nil {
		log = slog.Default()
	}
	return &SiteModem{
		id:                     id,
		cfg:                    cfg,
		log:                    log.With("site", cfg.Name, "remote", cfg.RemoteAddr),
		onRxFn:                 onRxFn,
		reqCh:                  make(chan arbReq, 256),
		clientWantSignalReport: false,
	}
}

func (s *SiteModem) IsConnected() bool {
	return s.connected.Load()
}

func (s *SiteModem) LastPongAgeSecs() float64 {
	ns := s.lastPongNs.Load()
	if ns == 0 {
		return -1
	}
	return time.Since(time.Unix(0, ns)).Seconds()
}

func (s *SiteModem) Run(ctx context.Context) error {
	var wg sync.WaitGroup

	if s.cfg.ListenAddr != "" {
		ln, err := net.Listen("tcp", s.cfg.ListenAddr)
		if err != nil {
			return fmt.Errorf("listen virtual KISS %s: %w", s.cfg.ListenAddr, err)
		}
		s.log.Info("virtual KISS listener ready", "listen", s.cfg.ListenAddr)

		wg.Add(1)
		go func() {
			defer wg.Done()
			<-ctx.Done()
			_ = ln.Close()
		}()

		wg.Add(1)
		go func() {
			defer wg.Done()
			s.acceptLoop(ctx, ln)
		}()
	}

	backoff := 1 * time.Second
	for {
		if ctx.Err() != nil {
			wg.Wait()
			return nil
		}

		err := s.runModemSession(ctx)
		s.connected.Store(false)
		s.dropClient()

		if ctx.Err() != nil {
			wg.Wait()
			return nil
		}
		s.log.Warn("modem session ended, reconnecting", "error", err, "backoff", backoff)

		select {
		case <-ctx.Done():
			wg.Wait()
			return nil
		case <-time.After(backoff):
		}
		backoff = min(backoff*2, 15*time.Second)
	}
}

func (s *SiteModem) runModemSession(ctx context.Context) error {
	dialer := net.Dialer{
		Timeout:   modemConnectTimeout,
		KeepAlive: 15 * time.Second,
	}
	conn, err := dialer.DialContext(ctx, "tcp", s.cfg.RemoteAddr)
	if err != nil {
		return fmt.Errorf("dial %s: %w", s.cfg.RemoteAddr, err)
	}
	if tc, ok := conn.(*net.TCPConn); ok {
		_ = tc.SetNoDelay(true)
	}

	sessionCtx, cancel := context.WithCancel(ctx)
	defer func() {
		cancel()
		_ = conn.Close()
	}()

	txDoneCh := make(chan hwFrame, 4)
	cmdRespCh := make(chan hwFrame, 8)
	readErrCh := make(chan error, 1)

	go s.readModemLoop(sessionCtx, conn, txDoneCh, cmdRespCh, readErrCh)

	// Initialize modem parameters before marking connected.
	if err := s.initModemHardware(sessionCtx, conn, cmdRespCh); err != nil {
		return fmt.Errorf("modem init: %w", err)
	}

	s.lastPongNs.Store(time.Now().UnixNano())
	s.connected.Store(true)
	s.log.Info("connected and configured KISS modem",
		"freq_mhz", s.cfg.FreqMHz, "bw_khz", s.cfg.BwKHz,
		"sf", s.cfg.SF, "cr", s.cfg.CR, "tx_dbm", s.cfg.TxPower)

	pingTicker := time.NewTicker(modemPingInterval)
	defer pingTicker.Stop()

	for {
		select {
		case <-sessionCtx.Done():
			return sessionCtx.Err()

		case err := <-readErrCh:
			return err

		case <-pingTicker.C:
			if _, err := s.execHwCmd(sessionCtx, conn, cmdRespCh, hardware.HW_CMD_PING, nil); err != nil {
				return fmt.Errorf("liveness ping failed: %w", err)
			}
			s.lastPongNs.Store(time.Now().UnixNano())

		case req := <-s.reqCh:
			switch req.kind {
			case reqKindRawFrame:
				_, err := conn.Write(req.rawFrame)
				if req.respCh != nil {
					req.respCh <- arbResp{err: err}
				}
				if err != nil {
					return err
				}

			case reqKindHwCmd:
				resp, err := s.execHwCmd(sessionCtx, conn, cmdRespCh, req.subCmd, req.payload)
				if err == nil {
					s.lastPongNs.Store(time.Now().UnixNano())
				}
				if req.respCh != nil {
					req.respCh <- arbResp{subCmd: resp.subCmd, data: resp.data, err: err}
				}

			case reqKindTx:
				res, err := s.execTx(sessionCtx, conn, txDoneCh, req.payload)
				if err != nil || res == 0 {
					s.txErrors.Add(1)
				} else {
					s.txPackets.Add(1)
				}
				if req.respCh != nil {
					req.respCh <- arbResp{subCmd: hardware.HW_RESP_TX_DONE, data: []byte{res}, err: err}
				}
			}
		}
	}
}

func (s *SiteModem) initModemHardware(ctx context.Context, conn net.Conn, cmdRespCh <-chan hwFrame) error {
	// Wait for the ESP32 KISS firmware to become responsive while keeping the TCP
	// connection open (opening the tty on first connect may reset the ESP32 or
	// catch it during a first-boot SPIFFS format / identity generation).
	if err := s.waitModemReady(ctx, conn, cmdRespCh); err != nil {
		return err
	}

	// Always keep signal reports enabled on the physical modem; virtual KISS translates per-client preference.
	if _, err := s.execHwCmd(ctx, conn, cmdRespCh, hardware.HW_CMD_SET_SIGNAL_REPORT, []byte{0x01}); err != nil {
		return fmt.Errorf("SET_SIGNAL_REPORT: %w", err)
	}

	var radioBuf [10]byte
	binary.LittleEndian.PutUint32(radioBuf[0:4], uint32(s.cfg.FreqMHz*1_000_000+0.5))
	binary.LittleEndian.PutUint32(radioBuf[4:8], uint32(s.cfg.BwKHz*1_000+0.5))
	radioBuf[8] = s.cfg.SF
	radioBuf[9] = s.cfg.CR
	if _, err := s.execHwCmd(ctx, conn, cmdRespCh, hardware.HW_CMD_SET_RADIO, radioBuf[:]); err != nil {
		return fmt.Errorf("SET_RADIO: %w", err)
	}

	if _, err := s.execHwCmd(ctx, conn, cmdRespCh, hardware.HW_CMD_SET_TX_POWER, []byte{s.cfg.TxPower}); err != nil {
		return fmt.Errorf("SET_TX_POWER: %w", err)
	}
	return nil
}

func (s *SiteModem) waitModemReady(ctx context.Context, conn net.Conn, cmdRespCh <-chan hwFrame) error {
	readyCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()

	pingFrame := hardware.EncodeHardwareFrame(0, hardware.HW_CMD_PING, nil)
	wantPong := hardware.HwResp(hardware.HW_CMD_PING)

	for {
		drainHwChan(cmdRespCh)
		_ = conn.SetWriteDeadline(time.Now().Add(modemCmdTimeout))
		_, writeErr := conn.Write(pingFrame)
		_ = conn.SetWriteDeadline(time.Time{})
		if writeErr != nil {
			return fmt.Errorf("PING write: %w", writeErr)
		}

		attemptTimer := time.NewTimer(500 * time.Millisecond)
		select {
		case <-readyCtx.Done():
			attemptTimer.Stop()
			if ctx.Err() != nil {
				return ctx.Err()
			}
			return errors.New("modem PING readiness timeout (check /dev/kiss-modem and firmware)")
		case resp := <-cmdRespCh:
			attemptTimer.Stop()
			if resp.subCmd == wantPong {
				// Settle any duplicate pong from an earlier probe before issuing config commands.
				time.Sleep(40 * time.Millisecond)
				drainHwChan(cmdRespCh)
				return nil
			}
		case <-attemptTimer.C:
		}
	}
}

func drainHwChan(ch <-chan hwFrame) {
	for {
		select {
		case <-ch:
		default:
			return
		}
	}
}

func (s *SiteModem) execHwCmd(ctx context.Context, conn net.Conn, cmdRespCh <-chan hwFrame, subCmd byte, payload []byte) (hwFrame, error) {
	drainHwChan(cmdRespCh)
	frame := hardware.EncodeHardwareFrame(0, subCmd, payload)
	if err := conn.SetWriteDeadline(time.Now().Add(modemCmdTimeout)); err != nil {
		return hwFrame{}, err
	}
	if _, err := conn.Write(frame); err != nil {
		return hwFrame{}, err
	}
	_ = conn.SetWriteDeadline(time.Time{})

	timer := time.NewTimer(modemCmdTimeout)
	defer timer.Stop()

	select {
	case <-ctx.Done():
		return hwFrame{}, ctx.Err()
	case <-timer.C:
		return hwFrame{}, fmt.Errorf("hw cmd 0x%02x timeout", subCmd)
	case resp := <-cmdRespCh:
		return resp, nil
	}
}

func (s *SiteModem) execTx(ctx context.Context, conn net.Conn, txDoneCh <-chan hwFrame, pkt []byte) (byte, error) {
	drainHwChan(txDoneCh)
	frame := hardware.EncodeDataFrame(pkt)
	if err := conn.SetWriteDeadline(time.Now().Add(modemCmdTimeout)); err != nil {
		return 0, err
	}
	if _, err := conn.Write(frame); err != nil {
		return 0, err
	}
	_ = conn.SetWriteDeadline(time.Time{})

	timer := time.NewTimer(modemTxTimeout)
	defer timer.Stop()

	select {
	case <-ctx.Done():
		return 0, ctx.Err()
	case <-timer.C:
		return 0, hardware.ErrTxTimeout
	case resp := <-txDoneCh:
		if resp.subCmd == hardware.HW_RESP_ERROR {
			return 0, hardware.ErrTxBusy
		}
		if len(resp.data) > 0 {
			return resp.data[0], nil
		}
		return 1, nil
	}
}

func (s *SiteModem) readModemLoop(ctx context.Context, conn net.Conn, txDoneCh chan<- hwFrame, cmdRespCh chan<- hwFrame, readErrCh chan<- error) {
	var stream []byte
	buf := make([]byte, 2048)

	for {
		n, err := conn.Read(buf)
		if n > 0 {
			stream = append(stream, buf[:n]...)
			frames, rem, _ := hardware.ExtractFrames(stream)
			stream = rem

			for _, f := range frames {
				if f.Port != 0 {
					continue
				}
				switch f.Command {
				case hardware.KISS_CMD_DATA:
					if len(f.Data) == 0 {
						continue
					}
					s.rxPackets.Add(1)
					pktCopy := append([]byte(nil), f.Data...)
					s.writeToClient(hardware.EncodeDataFrame(pktCopy), false)
					if s.onRxFn != nil {
						s.onRxFn(s.id, pktCopy)
					}

				case hardware.KISS_CMD_SETHARDWARE:
					subCmd, data, decErr := hardware.DecodeHardwareFrame(f)
					if decErr != nil {
						continue
					}
					dataCopy := append([]byte(nil), data...)
					switch subCmd {
					case hardware.HW_RESP_RX_META:
						s.writeToClient(hardware.EncodeHardwareFrame(0, subCmd, dataCopy), true)

					case hardware.HW_RESP_TX_DONE:
						select {
						case txDoneCh <- hwFrame{subCmd: subCmd, data: dataCopy}:
						default:
						}

					case hardware.HW_RESP_ERROR:
						if len(dataCopy) > 0 && dataCopy[0] == hardware.HW_ERR_TX_BUSY {
							select {
							case txDoneCh <- hwFrame{subCmd: subCmd, data: dataCopy}:
							default:
							}
						} else {
							select {
							case cmdRespCh <- hwFrame{subCmd: subCmd, data: dataCopy}:
							default:
							}
						}

					default:
						select {
						case cmdRespCh <- hwFrame{subCmd: subCmd, data: dataCopy}:
						default:
						}
					}
				}
			}
		}
		if err != nil {
			if ctx.Err() == nil {
				select {
				case readErrCh <- err:
				default:
				}
			}
			return
		}
	}
}

// BridgeSend transmits a packet bridged from the peer site onto this site's
// physical RF modem AND delivers it into the local OwlShack virtual KISS stream.
func (s *SiteModem) BridgeSend(ctx context.Context, pkt []byte) error {
	pktCopy := append([]byte(nil), pkt...)

	// Deliver to local OwlShack observer/companions as an inbound frame.
	s.deliverSyntheticRxToClient(pktCopy)

	if !s.IsConnected() {
		return hardware.ErrDisconnected
	}

	respCh := make(chan arbResp, 1)
	select {
	case <-ctx.Done():
		return ctx.Err()
	case s.reqCh <- arbReq{kind: reqKindTx, payload: pktCopy, respCh: respCh}:
	default:
		return errors.New("modem tx queue full")
	}

	select {
	case <-ctx.Done():
		return ctx.Err()
	case resp := <-respCh:
		return resp.err
	}
}

func (s *SiteModem) deliverSyntheticRxToClient(pkt []byte) {
	s.clientMu.Lock()
	defer s.clientMu.Unlock()
	if s.clientConn == nil {
		return
	}
	_ = s.clientConn.SetWriteDeadline(time.Now().Add(2 * time.Second))
	_, _ = s.clientConn.Write(hardware.EncodeDataFrame(pkt))
	if s.clientWantSignalReport {
		// Synthetic SNR = 0 dB, RSSI = -80 dBm so OwlShack pairs RX_META cleanly.
		rssi := int8(-80)
		_, _ = s.clientConn.Write(hardware.EncodeHardwareFrame(0, hardware.HW_RESP_RX_META, []byte{0x00, byte(rssi)}))
	}
	_ = s.clientConn.SetWriteDeadline(time.Time{})
}

func (s *SiteModem) writeToClient(rawFrame []byte, isSignalMeta bool) {
	s.clientMu.Lock()
	defer s.clientMu.Unlock()
	if s.clientConn == nil {
		return
	}
	if isSignalMeta && !s.clientWantSignalReport {
		return
	}
	_ = s.clientConn.SetWriteDeadline(time.Now().Add(2 * time.Second))
	_, _ = s.clientConn.Write(rawFrame)
	_ = s.clientConn.SetWriteDeadline(time.Time{})
}

func (s *SiteModem) dropClient() {
	s.clientMu.Lock()
	defer s.clientMu.Unlock()
	if s.clientConn != nil {
		_ = s.clientConn.Close()
		s.clientConn = nil
	}
}

func (s *SiteModem) acceptLoop(ctx context.Context, ln net.Listener) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			continue
		}
		if !s.IsConnected() {
			// Refuse while physical modem is down so OwlShack accurately reports disconnected.
			_ = conn.Close()
			continue
		}
		if tc, ok := conn.(*net.TCPConn); ok {
			_ = tc.SetNoDelay(true)
		}

		s.clientMu.Lock()
		if s.clientConn != nil {
			_ = s.clientConn.Close()
		}
		s.clientConn = conn
		s.clientWantSignalReport = false
		s.clientMu.Unlock()

		s.log.Info("OwlShack connected to virtual KISS port", "peer", conn.RemoteAddr().String())
		go s.handleClientConn(ctx, conn)
	}
}

func (s *SiteModem) handleClientConn(ctx context.Context, conn net.Conn) {
	defer func() {
		s.clientMu.Lock()
		if s.clientConn == conn {
			s.clientConn = nil
		}
		s.clientMu.Unlock()
		_ = conn.Close()
	}()

	var stream []byte
	buf := make([]byte, 2048)

	for {
		n, err := conn.Read(buf)
		if n > 0 {
			stream = append(stream, buf[:n]...)
			frames, rem, _ := hardware.ExtractFrames(stream)
			stream = rem

			for _, f := range frames {
				if f.Port != 0 {
					continue
				}
				if err := s.dispatchClientFrame(ctx, conn, f); err != nil {
					return
				}
			}
		}
		if err != nil {
			if !errors.Is(err, io.EOF) && ctx.Err() == nil {
				s.log.Debug("virtual KISS client closed", "error", err)
			}
			return
		}
	}
}

func (s *SiteModem) dispatchClientFrame(ctx context.Context, conn net.Conn, f *hardware.KissFrame) error {
	switch f.Command {
	case hardware.KISS_CMD_DATA:
		if len(f.Data) == 0 {
			return nil
		}
		pktCopy := append([]byte(nil), f.Data...)
		respCh := make(chan arbResp, 1)
		select {
		case <-ctx.Done():
			return ctx.Err()
		case s.reqCh <- arbReq{kind: reqKindTx, payload: pktCopy, respCh: respCh}:
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case resp := <-respCh:
			if errors.Is(resp.err, hardware.ErrTxBusy) {
				s.writeDirect(conn, hardware.EncodeHardwareFrame(0, hardware.HW_RESP_ERROR, []byte{hardware.HW_ERR_TX_BUSY}))
				return nil
			}
			if resp.err != nil {
				s.writeDirect(conn, hardware.EncodeHardwareFrame(0, hardware.HW_RESP_TX_DONE, []byte{0x00}))
				return nil
			}
			s.writeDirect(conn, hardware.EncodeHardwareFrame(0, resp.subCmd, resp.data))
			// Also bridge packets transmitted locally by OwlShack companions/repeaters!
			if s.onRxFn != nil {
				s.onRxFn(s.id, pktCopy)
			}
		}

	case hardware.KISS_CMD_SETHARDWARE:
		subCmd, data, err := hardware.DecodeHardwareFrame(f)
		if err != nil {
			return nil
		}
		switch subCmd {
		case hardware.HW_CMD_SET_SIGNAL_REPORT:
			want := len(data) > 0 && data[0] != 0
			s.clientMu.Lock()
			s.clientWantSignalReport = want
			s.clientMu.Unlock()
			val := byte(0)
			if want {
				val = 1
			}
			s.writeDirect(conn, hardware.EncodeHardwareFrame(0, hardware.HW_CMD_GET_SIGNAL_REPORT|0x80, []byte{val}))
			return nil

		case hardware.HW_CMD_GET_SIGNAL_REPORT:
			s.clientMu.Lock()
			want := s.clientWantSignalReport
			s.clientMu.Unlock()
			val := byte(0)
			if want {
				val = 1
			}
			s.writeDirect(conn, hardware.EncodeHardwareFrame(0, hardware.HW_CMD_GET_SIGNAL_REPORT|0x80, []byte{val}))
			return nil
		}

		respCh := make(chan arbResp, 1)
		select {
		case <-ctx.Done():
			return ctx.Err()
		case s.reqCh <- arbReq{kind: reqKindHwCmd, subCmd: subCmd, payload: append([]byte(nil), data...), respCh: respCh}:
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case resp := <-respCh:
			if resp.err == nil {
				s.writeDirect(conn, hardware.EncodeHardwareFrame(0, resp.subCmd, resp.data))
			}
		}

	case hardware.KISS_CMD_TXDELAY, hardware.KISS_CMD_PERSISTENCE,
		hardware.KISS_CMD_SLOTTIME, hardware.KISS_CMD_TXTAIL, hardware.KISS_CMD_FULLDUPLEX:
		raw := hardware.EncodeFrame(0, f.Command, f.Data)
		select {
		case s.reqCh <- arbReq{kind: reqKindRawFrame, rawFrame: raw}:
		default:
		}
	}
	return nil
}

func (s *SiteModem) writeDirect(conn net.Conn, raw []byte) {
	s.clientMu.Lock()
	defer s.clientMu.Unlock()
	if s.clientConn != conn {
		return
	}
	_ = conn.SetWriteDeadline(time.Now().Add(2 * time.Second))
	_, _ = conn.Write(raw)
	_ = conn.SetWriteDeadline(time.Time{})
}
