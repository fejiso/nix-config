package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

func main() {
	configPath := flag.String("config", "", "path to owlstack-bridge JSON config")
	debug := flag.Bool("debug", false, "enable debug logging")
	flag.Parse()

	if *configPath == "" {
		fmt.Fprintln(os.Stderr, "error: --config <path> is required")
		os.Exit(2)
	}

	level := slog.LevelInfo
	if *debug {
		level = slog.LevelDebug
	}
	log := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level}))
	slog.SetDefault(log)

	cfg, err := LoadConfig(*configPath)
	if err != nil {
		log.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	engine, err := NewBridgeEngine(cfg, log)
	if err != nil {
		log.Error("failed to initialize bridge engine", "error", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	var modems [2]*SiteModem

	onPacket := func(fromSite SiteID, raw []byte) {
		out, action, err := engine.RoutePacket(raw, fromSite, time.Now())
		if err != nil {
			log.Debug("dropped invalid packet", "from", siteName(cfg, fromSite), "error", err)
			return
		}
		if out == nil {
			return
		}

		toSite := SiteB
		if fromSite == SiteB {
			toSite = SiteA
		}

		log.Info("bridging packet",
			"from", siteName(cfg, fromSite),
			"to", siteName(cfg, toSite),
			"action", string(action),
			"len", len(out),
		)

		go func() {
			sendCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
			defer cancel()
			if err := modems[toSite].BridgeSend(sendCtx, out); err != nil {
				log.Warn("bridge send failed",
					"to", siteName(cfg, toSite),
					"action", string(action),
					"error", err,
				)
			}
		}()
	}

	modems[SiteA] = NewSiteModem(SiteA, cfg.SiteA, log, onPacket)
	modems[SiteB] = NewSiteModem(SiteB, cfg.SiteB, log, onPacket)

	// Reload allowlist on SIGHUP and watch AllowlistFile mtime if configured.
	sighup := make(chan os.Signal, 1)
	signal.Notify(sighup, syscall.SIGHUP)
	go func() {
		var lastMod time.Time
		if cfg.AllowlistFile != "" {
			if st, err := os.Stat(cfg.AllowlistFile); err == nil {
				lastMod = st.ModTime()
			}
		}
		ticker := time.NewTicker(15 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-sighup:
				if err := engine.ReloadAllowlist(); err != nil {
					log.Error("failed to reload allowlist on SIGHUP", "error", err)
				}
			case <-ticker.C:
				if cfg.AllowlistFile == "" {
					continue
				}
				if st, err := os.Stat(cfg.AllowlistFile); err == nil && !st.ModTime().Equal(lastMod) {
					lastMod = st.ModTime()
					if err := engine.ReloadAllowlist(); err != nil {
						log.Error("failed to reload changed allowlistFile", "error", err)
					}
				}
			}
		}
	}()

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		aUp := modems[SiteA].IsConnected()
		bUp := modems[SiteB].IsConnected()
		status := http.StatusOK
		if !aUp || !bUp {
			status = http.StatusServiceUnavailable
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"ok": aUp && bUp,
			cfg.SiteA.Name: map[string]any{
				"connected":       aUp,
				"lastPongAgeSecs": modems[SiteA].LastPongAgeSecs(),
			},
			cfg.SiteB.Name: map[string]any{
				"connected":       bUp,
				"lastPongAgeSecs": modems[SiteB].LastPongAgeSecs(),
			},
		})
	})

	mux.HandleFunc("/metrics", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		writeSiteMetrics(w, cfg.SiteA.Name, modems[SiteA], &engine.Counters[SiteA])
		writeSiteMetrics(w, cfg.SiteB.Name, modems[SiteB], &engine.Counters[SiteB])
	})

	httpSrv := &http.Server{
		Addr:              cfg.MetricsAddr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	var wg sync.WaitGroup
	wg.Add(3)
	go func() {
		defer wg.Done()
		_ = modems[SiteA].Run(ctx)
	}()
	go func() {
		defer wg.Done()
		_ = modems[SiteB].Run(ctx)
	}()
	go func() {
		defer wg.Done()
		log.Info("metrics/health HTTP server listening", "addr", cfg.MetricsAddr)
		if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("metrics server error", "error", err)
		}
	}()

	<-ctx.Done()
	shutCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_ = httpSrv.Shutdown(shutCtx)
	wg.Wait()
}

func siteName(cfg *Config, s SiteID) string {
	if s == SiteA {
		return cfg.SiteA.Name
	}
	return cfg.SiteB.Name
}

func writeSiteMetrics(w http.ResponseWriter, name string, m *SiteModem, c *BridgeCounters) {
	up := 0
	if m.IsConnected() {
		up = 1
	}
	fmt.Fprintf(w, "owlstack_modem_connected{site=%q} %d\n", name, up)
	fmt.Fprintf(w, "owlstack_modem_rx_packets_total{site=%q} %d\n", name, m.rxPackets.Load())
	fmt.Fprintf(w, "owlstack_modem_tx_packets_total{site=%q} %d\n", name, m.txPackets.Load())
	fmt.Fprintf(w, "owlstack_modem_tx_errors_total{site=%q} %d\n", name, m.txErrors.Load())
	fmt.Fprintf(w, "owlstack_bridge_packets_total{from=%q,action=\"flood_bridged\"} %d\n", name, c.FloodBridged.Load())
	fmt.Fprintf(w, "owlstack_bridge_packets_total{from=%q,action=\"scope_translated\"} %d\n", name, c.ScopeTranslated.Load())
	fmt.Fprintf(w, "owlstack_bridge_packets_total{from=%q,action=\"clamped_0hop\"} %d\n", name, c.ClampedZeroHop.Load())
	fmt.Fprintf(w, "owlstack_bridge_packets_total{from=%q,action=\"direct_wormhole\"} %d\n", name, c.DirectWormhole.Load())
	fmt.Fprintf(w, "owlstack_bridge_packets_total{from=%q,action=\"dedup_drop\"} %d\n", name, c.DedupDropped.Load())
}
