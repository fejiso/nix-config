package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"net"
	"testing"
	"time"

	meshcore "github.com/OwlShack/meshcore-go"
	"github.com/OwlShack/meshcore-go/hardware"
)

func newTestConfig(t *testing.T, allowedHex string) *Config {
	t.Helper()
	return &Config{
		StateDir:      t.TempDir(),
		AckWindowSecs: 30,
		MaxFloodHops:  16,
		AllowedCompanions: []CompanionEntry{
			{PubKey: allowedHex},
		},
		SiteA: SiteConfig{
			Name:         "pinto",
			RemoteAddr:   "127.0.0.1:19001",
			DefaultScope: "*",
			FreqMHz:      869.618,
			BwKHz:        62.5,
			SF:           8,
			CR:           8,
			TxPower:      20,
		},
		SiteB: SiteConfig{
			Name:         "dublin",
			RemoteAddr:   "127.0.0.1:19002",
			DefaultScope: "#ioi",
			FreqMHz:      869.618,
			BwKHz:        62.5,
			SF:           8,
			CR:           8,
			TxPower:      20,
		},
	}
}

func makeIdentityWithPrefix(t *testing.T, avoid byte) meshcore.LocalIdentity {
	t.Helper()
	for range 256 {
		id, err := meshcore.GenerateLocalIdentity(rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		pk := id.PublicKey()
		if pk[0] != 0x00 && pk[0] != 0xFF && pk[0] != avoid {
			return id
		}
	}
	t.Fatal("could not generate distinct identity")
	return meshcore.LocalIdentity{}
}

func TestAdvertAllowlistAndScopeTranslation(t *testing.T) {
	allowedID := makeIdentityWithPrefix(t, 0x00)
	strangerID := makeIdentityWithPrefix(t, allowedID.PublicKey()[0])

	allowedPK := allowedID.PublicKey()
	cfg := newTestConfig(t, hex.EncodeToString(allowedPK[:]))
	eng, err := NewBridgeEngine(cfg, nil)
	if err != nil {
		t.Fatal(err)
	}

	now := time.Now()
	ioi := meshcore.NewRegion("#ioi")

	// 1. Allowlisted companion sends unscoped ADVERT in Pinto -> must flood into Dublin with #ioi scope!
	advAllowed, err := meshcore.NewAdvert(allowedID, meshcore.AdvertAppData{
		Type: "CHAT",
		Name: "FerMobile",
	}, uint32(now.Unix()))
	if err != nil {
		t.Fatal(err)
	}
	advBytes, err := advAllowed.ToBytes()
	if err != nil {
		t.Fatal(err)
	}
	pktIn := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeAdvert, 0),
		PathLength: meshcore.MakePathLen(1, 1),
		Path:       []byte{0x42},
		Payload:    advBytes,
	}
	rawIn, err := pktIn.ToBytes()
	if err != nil {
		t.Fatal(err)
	}

	rawOut, action, err := eng.RoutePacket(rawIn, SiteA, now)
	if err != nil {
		t.Fatal(err)
	}
	if action != ActionFloodBridged {
		t.Fatalf("expected ActionFloodBridged, got %s", action)
	}

	pktOut, err := meshcore.PacketFromBytes(rawOut)
	if err != nil {
		t.Fatal(err)
	}
	if pktOut.RouteType() != meshcore.RouteTypeTransportFlood {
		t.Fatalf("expected RouteTypeTransportFlood in Dublin, got %s", pktOut.RouteTypeString())
	}
	if !ioi.MatchesPacket(pktOut) {
		t.Fatalf("expected #ioi transport code on Dublin egress, got 0x%04x", pktOut.TransportCode1)
	}
	// Original 1 hop + 2 bridge hops = 3 hops.
	if pktOut.PathHashCount() != 3 {
		t.Fatalf("expected 3 path hops (1 + 2 bridge), got %d", pktOut.PathHashCount())
	}

	// 2. Echo of the bridged packet heard back on Dublin RF -> must be dedup-dropped!
	echoOut, echoAction, err := eng.RoutePacket(rawOut, SiteB, now)
	if err != nil {
		t.Fatal(err)
	}
	if echoOut != nil || echoAction != ActionDedupDrop {
		t.Fatalf("expected echo to be dedup-dropped, got %s", echoAction)
	}

	// 3. Non-allowlisted stranger ADVERT in Dublin (#ioi scoped) -> must be clamped to 0-hop DIRECT in Pinto!
	advStranger, err := meshcore.NewAdvert(strangerID, meshcore.AdvertAppData{
		Type: "CHAT",
		Name: "RandomDublinNode",
	}, uint32(now.Unix())+1)
	if err != nil {
		t.Fatal(err)
	}
	strangerBytes, _ := advStranger.ToBytes()
	strangerPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeAdvert, 0),
		PathLength: meshcore.MakePathLen(1, 2),
		Path:       []byte{0xAA, 0xBB},
		Payload:    strangerBytes,
	}
	strangerPkt.SetScope(ioi)
	strangerRaw, _ := strangerPkt.ToBytes()

	clampedRaw, clampedAct, err := eng.RoutePacket(strangerRaw, SiteB, now)
	if err != nil {
		t.Fatal(err)
	}
	if clampedAct != ActionClampedZeroHop {
		t.Fatalf("expected ActionClampedZeroHop for stranger, got %s", clampedAct)
	}
	clampedPkt, err := meshcore.PacketFromBytes(clampedRaw)
	if err != nil {
		t.Fatal(err)
	}
	if clampedPkt.RouteType() != meshcore.RouteTypeDirect || clampedPkt.PathHashCount() != 0 || len(clampedPkt.Path) != 0 {
		t.Fatalf("expected 0-hop DIRECT, got route=%s hops=%d", clampedPkt.RouteTypeString(), clampedPkt.PathHashCount())
	}

	// 4. GRP_TXT on Public channel from "FerMobile" (learned from verified ADVERT) in Dublin (#ioi) -> floods unscoped in Pinto!
	pubCh := meshcore.PublicChannel()
	gtPayload := &meshcore.GroupTextPayload{
		Timestamp: uint32(now.Unix()) + 2,
		Sender:    "FerMobile",
		Text:      "hello from dublin",
	}
	gtEnc, err := gtPayload.Encrypt(pubCh.Hash, pubCh.PSK)
	if err != nil {
		t.Fatal(err)
	}
	gtBytes, _ := gtEnc.ToBytes()
	gtPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeGrpTxt, 0),
		PathLength: meshcore.MakePathLen(1, 0),
		Payload:    gtBytes,
	}
	gtPkt.SetScope(ioi)
	gtRaw, _ := gtPkt.ToBytes()

	gtOutRaw, gtAct, err := eng.RoutePacket(gtRaw, SiteB, now)
	if err != nil {
		t.Fatal(err)
	}
	if gtAct != ActionFloodBridged {
		t.Fatalf("expected GRP_TXT from verified companion name to flood, got %s", gtAct)
	}
	gtOutPkt, _ := meshcore.PacketFromBytes(gtOutRaw)
	if gtOutPkt.RouteType() != meshcore.RouteTypeFlood || gtOutPkt.IsTransport() {
		t.Fatalf("expected Dublin #ioi -> Pinto unscoped RouteTypeFlood, got %s", gtOutPkt.RouteTypeString())
	}
}

func TestDirectWormholeReturnRouting(t *testing.T) {
	allowedID := makeIdentityWithPrefix(t, 0x00)
	peerID := makeIdentityWithPrefix(t, allowedID.PublicKey()[0])
	allowedPK := allowedID.PublicKey()

	cfg := newTestConfig(t, hex.EncodeToString(allowedPK[:]))
	eng, err := NewBridgeEngine(cfg, nil)
	if err != nil {
		t.Fatal(err)
	}

	pintoBridge := eng.SiteBridgePubKey(SiteA)
	dublinBridge := eng.SiteBridgePubKey(SiteB)

	// Peer in Dublin replies via ROUTE_TYPE_DIRECT along reverse path: [dublinBridge, pintoBridge, 0x77]
	// targeting allowedID.PublicKey()[0].
	dmPayload := []byte{allowedPK[0], peerID.PublicKey()[0], 0x11, 0x22, 0x33, 0x44, 0x55}
	directIn := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeDirect, meshcore.PayloadTypeTxtMsg, 0),
		PathLength: meshcore.MakePathLen(1, 3),
		Path:       []byte{dublinBridge[0], pintoBridge[0], 0x77},
		Payload:    dmPayload,
	}
	rawIn, _ := directIn.ToBytes()

	rawOut, act, err := eng.RoutePacket(rawIn, SiteB, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if act != ActionDirectWormhole {
		t.Fatalf("expected ActionDirectWormhole, got %s", act)
	}
	pktOut, _ := meshcore.PacketFromBytes(rawOut)
	if pktOut.RouteType() != meshcore.RouteTypeDirect || pktOut.PathHashCount() != 1 || !bytes.Equal(pktOut.Path, []byte{0x77}) {
		t.Fatalf("expected remaining path [0x77], got hops=%d path=%x", pktOut.PathHashCount(), pktOut.Path)
	}
}

func TestKissArbiterWithFakeModemAndVirtualClient(t *testing.T) {
	// Fake remote ser2net KISS modem TCP server.
	modemLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer modemLn.Close()

	virtualLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	virtualAddr := virtualLn.Addr().String()
	_ = virtualLn.Close()

	modemTxReceived := make(chan []byte, 4)

	go func() {
		conn, err := modemLn.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		var stream []byte
		buf := make([]byte, 1024)
		for {
			n, err := conn.Read(buf)
			if n > 0 {
				stream = append(stream, buf[:n]...)
				frames, rem, _ := hardware.ExtractFrames(stream)
				stream = rem
				for _, f := range frames {
					switch f.Command {
					case hardware.KISS_CMD_SETHARDWARE:
						sub, _, _ := hardware.DecodeHardwareFrame(f)
						switch sub {
						case hardware.HW_CMD_SET_SIGNAL_REPORT:
							_, _ = conn.Write(hardware.EncodeHardwareFrame(0, hardware.HW_CMD_GET_SIGNAL_REPORT|0x80, []byte{0x01}))
						case hardware.HW_CMD_SET_RADIO, hardware.HW_CMD_SET_TX_POWER:
							_, _ = conn.Write(hardware.EncodeHardwareFrame(0, hardware.HW_RESP_OK, nil))
						case hardware.HW_CMD_PING:
							_, _ = conn.Write(hardware.EncodeHardwareFrame(0, hardware.HW_CMD_PING|0x80, nil))
						}
					case hardware.KISS_CMD_DATA:
						modemTxReceived <- append([]byte(nil), f.Data...)
						_, _ = conn.Write(hardware.EncodeHardwareFrame(0, hardware.HW_RESP_TX_DONE, []byte{0x01}))
					}
				}
			}
			if err != nil {
				return
			}
		}
	}()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	site := NewSiteModem(SiteA, SiteConfig{
		Name:         "pinto",
		RemoteAddr:   modemLn.Addr().String(),
		ListenAddr:   virtualAddr,
		DefaultScope: "*",
		FreqMHz:      869.618,
		BwKHz:        62.5,
		SF:           8,
		CR:           8,
		TxPower:      20,
	}, nil, nil)

	go func() { _ = site.Run(ctx) }()

	deadline := time.Now().Add(3 * time.Second)
	for !site.IsConnected() && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if !site.IsConnected() {
		t.Fatal("site modem failed to connect to fake modem")
	}

	// Connect virtual OwlShack client and verify BridgeSend injects RX + RX_META while physical modem gets TX!
	clientConn, err := net.DialTimeout("tcp", virtualAddr, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer clientConn.Close()

	// Enable signal report on virtual client.
	_, _ = clientConn.Write(hardware.EncodeHardwareFrame(0, hardware.HW_CMD_SET_SIGNAL_REPORT, []byte{0x01}))

	testPkt := []byte{meshcore.MakeHeader(meshcore.RouteTypeDirect, meshcore.PayloadTypeAck, 0), 0x00, 1, 2, 3, 4}
	if err := site.BridgeSend(ctx, testPkt); err != nil {
		t.Fatalf("BridgeSend failed: %v", err)
	}

	select {
	case got := <-modemTxReceived:
		if !bytes.Equal(got, testPkt) {
			t.Fatalf("physical modem got %x, want %x", got, testPkt)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for physical modem TX")
	}
}
