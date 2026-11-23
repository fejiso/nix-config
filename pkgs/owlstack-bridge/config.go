package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type SiteConfig struct {
	Name         string  `json:"name"`
	RemoteAddr   string  `json:"remoteAddr"`
	ListenAddr   string  `json:"listenAddr"`
	DefaultScope string  `json:"defaultScope"` // "*" for unscoped, or "#region" (e.g. "#ioi")
	FreqMHz      float64 `json:"freqMHz"`
	BwKHz        float64 `json:"bwKHz"`
	SF           uint8   `json:"sf"`
	CR           uint8   `json:"cr"`
	TxPower      uint8   `json:"txPower"`
}

type CompanionEntry struct {
	PubKey string `json:"pubKey"`
	Name   string `json:"name,omitempty"`
}

type ChannelConfig struct {
	Name      string `json:"name"`
	PSKBase64 string `json:"pskBase64,omitempty"` // empty for "#hashtag" channels
	HomeSite  string `json:"homeSite,omitempty"`  // optional home site name (e.g. "pinto" or "dublin") for zeroHopChannels
}

type AllowlistData struct {
	AllowedCompanions []CompanionEntry `json:"allowedCompanions"`
	BridgedChannels   []ChannelConfig  `json:"bridgedChannels,omitempty"`
	ZeroHopChannels   []ChannelConfig  `json:"zeroHopChannels,omitempty"`
	ExtraChannels     []ChannelConfig  `json:"extraChannels,omitempty"` // deprecated: local-only OwlShack channels, ignored by bridge
}

type Config struct {
	StateDir          string           `json:"stateDir"`
	MetricsAddr       string           `json:"metricsAddr"`
	AllowlistFile     string           `json:"allowlistFile,omitempty"`
	AllowedCompanions []CompanionEntry `json:"allowedCompanions"`
	BridgedChannels   []ChannelConfig  `json:"bridgedChannels,omitempty"`
	ZeroHopChannels   []ChannelConfig  `json:"zeroHopChannels,omitempty"`
	ExtraChannels     []ChannelConfig  `json:"extraChannels,omitempty"` // deprecated: local-only OwlShack channels, ignored by bridge
	AckWindowSecs     int              `json:"ackWindowSecs"`
	MaxFloodHops      int              `json:"maxFloodHops"`
	SiteA             SiteConfig       `json:"siteA"`
	SiteB             SiteConfig       `json:"siteB"`
}

func applySiteDefaults(s *SiteConfig) {
	if s.DefaultScope == "" {
		s.DefaultScope = "*"
	}
	if s.FreqMHz == 0 {
		s.FreqMHz = 869.618
	}
	if s.BwKHz == 0 {
		s.BwKHz = 62.5
	}
	if s.SF == 0 {
		s.SF = 8
	}
	if s.CR == 0 {
		s.CR = 8
	}
	if s.TxPower == 0 {
		s.TxPower = 20
	}
}

func LoadConfig(path string) (*Config, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config %s: %w", path, err)
	}
	var cfg Config
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return nil, fmt.Errorf("parse config %s: %w", path, err)
	}
	if cfg.AckWindowSecs <= 0 {
		cfg.AckWindowSecs = 30
	}
	if cfg.MaxFloodHops <= 0 {
		cfg.MaxFloodHops = 16
	}
	if cfg.MetricsAddr == "" {
		cfg.MetricsAddr = "0.0.0.0:9620"
	}
	applySiteDefaults(&cfg.SiteA)
	applySiteDefaults(&cfg.SiteB)

	if cfg.SiteA.Name == "" || cfg.SiteB.Name == "" {
		return nil, fmt.Errorf("both siteA.name and siteB.name are required")
	}
	if cfg.SiteA.RemoteAddr == "" || cfg.SiteB.RemoteAddr == "" {
		return nil, fmt.Errorf("both siteA.remoteAddr and siteB.remoteAddr are required")
	}
	return &cfg, nil
}

// LoadAllowlistFile reads an optional runtime allowlist file (either JSON
// matching AllowlistData, or newline-delimited hex pubkeys with '#' comments).
func LoadAllowlistFile(path string) (*AllowlistData, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	trimmed := strings.TrimSpace(string(raw))
	if trimmed == "" {
		return &AllowlistData{}, nil
	}
	if strings.HasPrefix(trimmed, "{") {
		var data AllowlistData
		if err := json.Unmarshal([]byte(trimmed), &data); err != nil {
			return nil, fmt.Errorf("parse JSON allowlist %s: %w", path, err)
		}
		return &data, nil
	}

	var out AllowlistData
	sc := bufio.NewScanner(strings.NewReader(trimmed))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if idx := strings.IndexByte(line, '#'); idx >= 0 {
			line = strings.TrimSpace(line[:idx])
		}
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		entry := CompanionEntry{PubKey: fields[0]}
		if len(fields) > 1 {
			entry.Name = strings.Join(fields[1:], " ")
		}
		out.AllowedCompanions = append(out.AllowedCompanions, entry)
	}
	return &out, sc.Err()
}
