package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	meshcore "github.com/OwlShack/meshcore-go"
)

type SiteID int

const (
	SiteA SiteID = 0
	SiteB SiteID = 1
)

type BridgeAction string

const (
	ActionFloodBridged    BridgeAction = "flood_bridged"
	ActionClampedZeroHop  BridgeAction = "clamped_0hop"
	ActionDirectWormhole  BridgeAction = "direct_wormhole"
	ActionDedupDrop       BridgeAction = "dedup_drop"
	ActionHopLimitDrop    BridgeAction = "hop_limit_drop"
	ActionLocalDirectSkip BridgeAction = "local_direct_skip"
	ActionInvalidDrop     BridgeAction = "invalid_drop"
)

type parsedCompanion struct {
	keyPrefix []byte
	name      string
}

type BridgeCounters struct {
	FloodBridged    atomic.Uint64
	ScopeTranslated atomic.Uint64
	ClampedZeroHop  atomic.Uint64
	DirectWormhole  atomic.Uint64
	DedupDropped    atomic.Uint64
	HopLimitDropped atomic.Uint64
	InvalidDropped  atomic.Uint64
}

type persistedIdentities struct {
	SiteAPubHex string `json:"siteAPubHex"`
	SiteBPubHex string `json:"siteBPubHex"`
}

type BridgeEngine struct {
	cfg *Config
	log *slog.Logger

	siteRegion    [2]*meshcore.Region
	siteBridgePub [2][meshcore.PubKeySize]byte

	mu             sync.RWMutex
	companions     []parsedCompanion
	channels       []*meshcore.ChannelEntry
	learnedNames   map[string]string // hex pubkey -> verified ADVERT name
	ackWindowUntil time.Time

	dedupMu sync.Mutex
	dedup   meshcore.DedupCache

	Counters [2]BridgeCounters // indexed by source SiteID
}

func NewBridgeEngine(cfg *Config, log *slog.Logger) (*BridgeEngine, error) {
	if log == nil {
		log = slog.Default()
	}
	b := &BridgeEngine{
		cfg:          cfg,
		log:          log,
		learnedNames: make(map[string]string),
	}

	var err error
	if b.siteRegion[SiteA], err = parseDefaultRegion(cfg.SiteA.DefaultScope); err != nil {
		return nil, fmt.Errorf("siteA defaultScope: %w", err)
	}
	if b.siteRegion[SiteB], err = parseDefaultRegion(cfg.SiteB.DefaultScope); err != nil {
		return nil, fmt.Errorf("siteB defaultScope: %w", err)
	}

	if err := b.initPersistence(); err != nil {
		return nil, err
	}
	if err := b.ReloadAllowlist(); err != nil {
		return nil, err
	}
	return b, nil
}

func parseDefaultRegion(scope string) (*meshcore.Region, error) {
	scope = strings.TrimSpace(scope)
	if scope == "" || scope == "*" {
		return nil, nil
	}
	r := meshcore.NewRegion(scope)
	if r.Key.IsZero() {
		return nil, fmt.Errorf("region %q produced a zero key", scope)
	}
	return r, nil
}

func generateBridgePub(avoidFirstByte int) ([meshcore.PubKeySize]byte, error) {
	var out [meshcore.PubKeySize]byte
	for range 256 {
		pub, _, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			return out, err
		}
		if pub[0] == 0x00 || pub[0] == 0xFF || int(pub[0]) == avoidFirstByte {
			continue
		}
		copy(out[:], pub)
		return out, nil
	}
	return out, fmt.Errorf("failed to generate valid bridge public key")
}

func (b *BridgeEngine) initPersistence() error {
	if b.cfg.StateDir != "" {
		if err := os.MkdirAll(b.cfg.StateDir, 0o750); err != nil {
			return fmt.Errorf("mkdir stateDir %s: %w", b.cfg.StateDir, err)
		}
		idPath := filepath.Join(b.cfg.StateDir, "bridge_identities.json")
		if raw, err := os.ReadFile(idPath); err == nil {
			var p persistedIdentities
			if json.Unmarshal(raw, &p) == nil {
				aBytes, errA := hex.DecodeString(p.SiteAPubHex)
				bBytes, errB := hex.DecodeString(p.SiteBPubHex)
				if errA == nil && errB == nil && len(aBytes) == meshcore.PubKeySize && len(bBytes) == meshcore.PubKeySize {
					copy(b.siteBridgePub[SiteA][:], aBytes)
					copy(b.siteBridgePub[SiteB][:], bBytes)
				}
			}
		}

		namesPath := filepath.Join(b.cfg.StateDir, "learned_names.json")
		if raw, err := os.ReadFile(namesPath); err == nil {
			_ = json.Unmarshal(raw, &b.learnedNames)
		}
	}

	var zero [meshcore.PubKeySize]byte
	if b.siteBridgePub[SiteA] == zero || b.siteBridgePub[SiteB] == zero {
		pubA, err := generateBridgePub(-1)
		if err != nil {
			return err
		}
		pubB, err := generateBridgePub(int(pubA[0]))
		if err != nil {
			return err
		}
		b.siteBridgePub[SiteA] = pubA
		b.siteBridgePub[SiteB] = pubB

		if b.cfg.StateDir != "" {
			idPath := filepath.Join(b.cfg.StateDir, "bridge_identities.json")
			raw, _ := json.MarshalIndent(persistedIdentities{
				SiteAPubHex: hex.EncodeToString(pubA[:]),
				SiteBPubHex: hex.EncodeToString(pubB[:]),
			}, "", "  ")
			_ = os.WriteFile(idPath, raw, 0o640)
		}
	}
	return nil
}

func (b *BridgeEngine) saveLearnedNamesLocked() {
	if b.cfg.StateDir == "" {
		return
	}
	namesPath := filepath.Join(b.cfg.StateDir, "learned_names.json")
	if raw, err := json.MarshalIndent(b.learnedNames, "", "  "); err == nil {
		_ = os.WriteFile(namesPath, raw, 0o640)
	}
}

func (b *BridgeEngine) SiteBridgePubKey(s SiteID) [meshcore.PubKeySize]byte {
	return b.siteBridgePub[s]
}

func (b *BridgeEngine) ReloadAllowlist() error {
	entries := append([]CompanionEntry(nil), b.cfg.AllowedCompanions...)
	chConfigs := append([]ChannelConfig(nil), b.cfg.ExtraChannels...)

	if b.cfg.AllowlistFile != "" {
		extra, err := LoadAllowlistFile(b.cfg.AllowlistFile)
		if err != nil {
			if !os.IsNotExist(err) {
				return fmt.Errorf("load allowlistFile: %w", err)
			}
		} else {
			entries = append(entries, extra.AllowedCompanions...)
			chConfigs = append(chConfigs, extra.ExtraChannels...)
		}
	}

	var parsed []parsedCompanion
	for _, e := range entries {
		clean := strings.TrimPrefix(strings.TrimSpace(e.PubKey), "0x")
		if clean == "" {
			continue
		}
		decoded, err := hex.DecodeString(clean)
		if err != nil || len(decoded) == 0 || len(decoded) > meshcore.PubKeySize {
			return fmt.Errorf("invalid companion pubKey %q: must be 2..64 hex chars", e.PubKey)
		}
		parsed = append(parsed, parsedCompanion{
			keyPrefix: decoded,
			name:      strings.TrimSpace(e.Name),
		})
	}

	channels := []*meshcore.ChannelEntry{meshcore.PublicChannel()}
	seenChan := map[string]bool{"Public": true}

	addHashtag := func(tag string) {
		tag = strings.TrimSpace(tag)
		if tag == "" || tag == "*" {
			return
		}
		norm := meshcore.NormalizeHashtag(tag)
		if seenChan[norm] {
			return
		}
		seenChan[norm] = true
		channels = append(channels, meshcore.NewChannelFromHashtag(norm))
	}

	addHashtag(b.cfg.SiteA.DefaultScope)
	addHashtag(b.cfg.SiteB.DefaultScope)

	for _, cc := range chConfigs {
		name := strings.TrimSpace(cc.Name)
		if name == "" {
			continue
		}
		if cc.PSKBase64 != "" {
			ch, err := meshcore.NewChannelFromBase64(name, strings.TrimSpace(cc.PSKBase64))
			if err != nil {
				return fmt.Errorf("channel %q PSK: %w", name, err)
			}
			channels = append(channels, ch)
		} else {
			addHashtag(name)
		}
	}

	b.mu.Lock()
	b.companions = parsed
	b.channels = channels
	b.mu.Unlock()

	b.log.Info("loaded allowlist",
		"companions", len(parsed),
		"channels", len(channels),
		"siteA_bridge_hash", fmt.Sprintf("%02x", b.siteBridgePub[SiteA][0]),
		"siteB_bridge_hash", fmt.Sprintf("%02x", b.siteBridgePub[SiteB][0]),
	)
	return nil
}

func (b *BridgeEngine) matchPubKeyLocked(pubKey []byte) bool {
	for _, c := range b.companions {
		if len(pubKey) >= len(c.keyPrefix) && bytes.Equal(pubKey[:len(c.keyPrefix)], c.keyPrefix) {
			return true
		}
	}
	return false
}

func (b *BridgeEngine) matchHash1Locked(h byte) bool {
	for _, c := range b.companions {
		if c.keyPrefix[0] == h {
			return true
		}
	}
	return false
}

func (b *BridgeEngine) matchSenderNameLocked(sender string) bool {
	if sender == "" {
		return false
	}
	for _, c := range b.companions {
		if c.name != "" && c.name == sender {
			return true
		}
		if len(c.keyPrefix) == meshcore.PubKeySize {
			if learned, ok := b.learnedNames[hex.EncodeToString(c.keyPrefix)]; ok && learned == sender {
				return true
			}
		} else {
			for pubHex, learned := range b.learnedNames {
				if learned == sender {
					if pubBytes, err := hex.DecodeString(pubHex); err == nil && len(pubBytes) >= len(c.keyPrefix) && bytes.Equal(pubBytes[:len(c.keyPrefix)], c.keyPrefix) {
						return true
					}
				}
			}
		}
	}
	return false
}

func (b *BridgeEngine) openAckWindowLocked(now time.Time) {
	until := now.Add(time.Duration(b.cfg.AckWindowSecs) * time.Second)
	if until.After(b.ackWindowUntil) {
		b.ackWindowUntil = until
	}
}

func (b *BridgeEngine) isAllowedFlood(pkt *meshcore.Packet, now time.Time) bool {
	b.mu.Lock()
	defer b.mu.Unlock()

	if len(b.companions) == 0 {
		return false
	}

	switch pkt.PayloadType() {
	case meshcore.PayloadTypeAdvert:
		adv, err := meshcore.AdvertFromBytes(pkt.Payload)
		if err != nil || !adv.Verify() {
			return false
		}
		pubBytes := adv.PublicKey.PublicKeyBytes()
		if !b.matchPubKeyLocked(pubBytes) {
			return false
		}
		appData := adv.AppData()
		if adv.AppDataErr() == nil && appData.Name != "" {
			pubHex := hex.EncodeToString(pubBytes)
			if b.learnedNames[pubHex] != appData.Name {
				b.learnedNames[pubHex] = appData.Name
				b.saveLearnedNamesLocked()
				b.log.Info("learned allowlisted companion name from verified ADVERT",
					"pub_key", pubHex[:16]+"...", "name", appData.Name)
			}
		}
		return true

	case meshcore.PayloadTypeAnonReq:
		if len(pkt.Payload) < 1+meshcore.PubKeySize+2 {
			return false
		}
		destHash := pkt.Payload[0]
		senderPub := pkt.Payload[1 : 1+meshcore.PubKeySize]
		if b.matchPubKeyLocked(senderPub) || b.matchHash1Locked(destHash) {
			b.openAckWindowLocked(now)
			return true
		}
		return false

	case meshcore.PayloadTypeTxtMsg, meshcore.PayloadTypeReq,
		meshcore.PayloadTypeResponse, meshcore.PayloadTypePath:
		if len(pkt.Payload) < 4 {
			return false
		}
		destHash := pkt.Payload[0]
		srcHash := pkt.Payload[1]
		if b.matchHash1Locked(srcHash) || b.matchHash1Locked(destHash) {
			b.openAckWindowLocked(now)
			return true
		}
		return false

	case meshcore.PayloadTypeGrpTxt:
		gt, err := meshcore.GroupTextFromBytes(pkt.Payload)
		if err != nil {
			return false
		}
		for _, ch := range b.channels {
			if ch.Hash != gt.ChannelHash {
				continue
			}
			gp, err := gt.DecryptStruct(ch.PSK)
			if err != nil {
				continue
			}
			if b.matchSenderNameLocked(gp.Sender) {
				return true
			}
		}
		return false

	case meshcore.PayloadTypeAck:
		return now.Before(b.ackWindowUntil)

	case meshcore.PayloadTypeMultiPart:
		mp, err := meshcore.MultiPartFromBytes(pkt.Payload)
		if err == nil && mp.WrappedType == meshcore.PayloadTypeAck {
			return now.Before(b.ackWindowUntil)
		}
		return false
	}

	return false
}

// RoutePacket evaluates raw MeshCore packet bytes received at fromSite and
// returns the rewritten wire bytes to transmit on the peer site (or nil if dropped).
func (b *BridgeEngine) RoutePacket(raw []byte, fromSite SiteID, now time.Time) ([]byte, BridgeAction, error) {
	pkt, err := meshcore.PacketFromBytes(raw)
	if err != nil {
		b.Counters[fromSite].InvalidDropped.Add(1)
		return nil, ActionInvalidDrop, err
	}
	if err := pkt.Validate(); err != nil {
		b.Counters[fromSite].InvalidDropped.Add(1)
		return nil, ActionInvalidDrop, err
	}

	toSite := SiteB
	if fromSite == SiteB {
		toSite = SiteA
	}

	// Direct routing handling (before general dedup check only for local non-bridge hops so we don't pollute dedup unnecessarily).
	if pkt.IsRouteDirect() {
		if pkt.PathHashCount() >= 2 {
			hashes := pkt.PathHashes()
			hSize := int(pkt.PathHashSize())
			srcPub := b.siteBridgePub[fromSite]
			dstPub := b.siteBridgePub[toSite]
			if bytes.Equal(hashes[0], srcPub[:hSize]) && bytes.Equal(hashes[1], dstPub[:hSize]) {
				if b.hasSeenOrMark(pkt) {
					b.Counters[fromSite].DedupDropped.Add(1)
					return nil, ActionDedupDrop, nil
				}
				clone := pkt.Clone()
				clone.RemoveFirstPathHash()
				clone.RemoveFirstPathHash()
				clone.Header = meshcore.MakeHeader(meshcore.RouteTypeDirect, clone.PayloadType(), clone.PayloadVer())
				clone.TransportCode1, clone.TransportCode2 = 0, 0

				// Only allowlisted traffic (or active-window ACKs) may continue multi-hop on the destination mesh.
				if clone.PathHashCount() > 0 && !b.isAllowedFlood(clone, now) {
					clone.Path = nil
					clone.PathLength = meshcore.MakePathLen(pkt.PathHashSize(), 0)
				}
				out, err := clone.ToBytes()
				if err != nil {
					return nil, ActionInvalidDrop, err
				}
				b.Counters[fromSite].DirectWormhole.Add(1)
				return out, ActionDirectWormhole, nil
			}
		}
		if pkt.PathHashCount() > 0 {
			// Local multi-hop unicast addressed to a local repeater, not the bridge.
			return nil, ActionLocalDirectSkip, nil
		}
	}

	if b.hasSeenOrMark(pkt) {
		b.Counters[fromSite].DedupDropped.Add(1)
		return nil, ActionDedupDrop, nil
	}

	if pkt.IsRouteFlood() {
		if int(pkt.PathHashCount()) > b.cfg.MaxFloodHops {
			b.Counters[fromSite].HopLimitDropped.Add(1)
			return nil, ActionHopLimitDrop, nil
		}

		if !pkt.IsShare() && b.isAllowedFlood(pkt, now) {
			clone := pkt.Clone()

			fromRegion := b.siteRegion[fromSite]
			toRegion := b.siteRegion[toSite]

			inDefaultScope := false
			if fromRegion == nil {
				// Source default scope is unscoped ("*").
				inDefaultScope = !clone.IsTransport() || clone.TransportCode1 == 0
			} else {
				// Source default scope is a named region (e.g. "#ioi"); also translate plain unscoped floods from allowlisted companions.
				inDefaultScope = fromRegion.MatchesPacket(clone) || !clone.IsTransport() || clone.TransportCode1 == 0
			}

			if inDefaultScope && ! sameScope(fromRegion, toRegion) {
				clone.SetScope(toRegion)
				b.Counters[fromSite].ScopeTranslated.Add(1)
			}

			// Append both bridge endpoints to Path so remote nodes learn a direct return route back across the bridge.
			srcPub := b.siteBridgePub[fromSite]
			dstPub := b.siteBridgePub[toSite]
			clone.AppendPathHash(srcPub[:])
			clone.AppendPathHash(dstPub[:])

			out, err := clone.ToBytes()
			if err != nil {
				return nil, ActionInvalidDrop, err
			}
			b.Counters[fromSite].FloodBridged.Add(1)
			return out, ActionFloodBridged, nil
		}
	}

	// Non-allowlisted flood, zero-hop share, or local 0-hop packet:
	// Clamp to single-hop (0-hop ROUTE_TYPE_DIRECT) so 1-hop RF neighbors and
	// remote OwlShack receive it without any repeater re-flooding the mesh extreme.
	clone := pkt.Clone()
	hashSize := pkt.PathHashSize()
	clone.Header = meshcore.MakeHeader(meshcore.RouteTypeDirect, clone.PayloadType(), clone.PayloadVer())
	clone.TransportCode1 = 0
	clone.TransportCode2 = 0
	clone.Path = nil
	clone.PathLength = meshcore.MakePathLen(hashSize, 0)

	out, err := clone.ToBytes()
	if err != nil {
		return nil, ActionInvalidDrop, err
	}
	b.Counters[fromSite].ClampedZeroHop.Add(1)
	return out, ActionClampedZeroHop, nil
}

func sameScope(a, b *meshcore.Region) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	return a.Key == b.Key
}

func (b *BridgeEngine) hasSeenOrMark(pkt *meshcore.Packet) bool {
	b.dedupMu.Lock()
	defer b.dedupMu.Unlock()
	return b.dedup.HasSeen(pkt)
}
