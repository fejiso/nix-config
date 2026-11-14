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
	ActionIdentityBridged BridgeAction = "identity_bridged"
	ActionChannelBridged  BridgeAction = "channel_bridged"
	ActionZeroHopFlood    BridgeAction = "zerohop_flood"
	ActionZeroHopClamped  BridgeAction = "zerohop_clamped"
	ActionDirectWormhole  BridgeAction = "direct_wormhole"
	ActionFilteredDrop    BridgeAction = "filtered_drop"
	ActionDedupDrop       BridgeAction = "dedup_drop"
	ActionHopLimitDrop    BridgeAction = "hop_limit_drop"
	ActionInvalidDrop     BridgeAction = "invalid_drop"
)

type parsedCompanion struct {
	keyPrefix []byte
	name      string
}

type BridgeCounters struct {
	IdentityBridged atomic.Uint64
	ChannelBridged  atomic.Uint64
	ZeroHopFlood    atomic.Uint64
	ZeroHopClamped  atomic.Uint64
	ScopeTranslated atomic.Uint64
	DirectWormhole  atomic.Uint64
	FilteredDropped atomic.Uint64
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

	mu              sync.RWMutex
	companions      []parsedCompanion
	bridgedChannels []*meshcore.ChannelEntry
	zeroHopChannels []*meshcore.ChannelEntry
	learnedNames    map[string]string // hex pubkey -> verified ADVERT name
	ackWindowUntil  time.Time

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

func parseChannelConfigs(label string, chConfigs []ChannelConfig) ([]*meshcore.ChannelEntry, []string, error) {
	var out []*meshcore.ChannelEntry
	seen := map[string]bool{}
	var names []string

	for _, cc := range chConfigs {
		name := strings.TrimSpace(cc.Name)
		if name == "" || name == "*" {
			continue
		}
		psk := strings.TrimSpace(cc.PSKBase64)
		if psk != "" {
			key := name + "\x00" + psk
			if seen[key] {
				continue
			}
			seen[key] = true
			ch, err := meshcore.NewChannelFromBase64(name, psk)
			if err != nil {
				return nil, nil, fmt.Errorf("%s %q PSK: %w", label, name, err)
			}
			out = append(out, ch)
			names = append(names, name)
		} else if strings.EqualFold(name, "Public") {
			if seen["Public"] {
				continue
			}
			seen["Public"] = true
			out = append(out, meshcore.PublicChannel())
			names = append(names, "Public")
		} else {
			norm := meshcore.NormalizeHashtag(name)
			if seen[norm] {
				continue
			}
			seen[norm] = true
			out = append(out, meshcore.NewChannelFromHashtag(norm))
			names = append(names, norm)
		}
	}
	return out, names, nil
}

func (b *BridgeEngine) ReloadAllowlist() error {
	entries := append([]CompanionEntry(nil), b.cfg.AllowedCompanions...)
	bridgedCfgs := append([]ChannelConfig(nil), b.cfg.BridgedChannels...)
	zeroHopCfgs := append([]ChannelConfig(nil), b.cfg.ZeroHopChannels...)

	if b.cfg.AllowlistFile != "" {
		extra, err := LoadAllowlistFile(b.cfg.AllowlistFile)
		if err != nil {
			if !os.IsNotExist(err) {
				return fmt.Errorf("load allowlistFile: %w", err)
			}
		} else {
			entries = append(entries, extra.AllowedCompanions...)
			bridgedCfgs = append(bridgedCfgs, extra.BridgedChannels...)
			zeroHopCfgs = append(zeroHopCfgs, extra.ZeroHopChannels...)
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

	bridgedChannels, bridgedNames, err := parseChannelConfigs("bridgedChannel", bridgedCfgs)
	if err != nil {
		return err
	}
	zeroHopChannels, zeroHopNames, err := parseChannelConfigs("zeroHopChannel", zeroHopCfgs)
	if err != nil {
		return err
	}

	b.mu.Lock()
	b.companions = parsed
	b.bridgedChannels = bridgedChannels
	b.zeroHopChannels = zeroHopChannels
	b.mu.Unlock()

	b.log.Info("loaded bridge policy",
		"companions", len(parsed),
		"bridged_channels", bridgedNames,
		"zerohop_channels", zeroHopNames,
		"siteA_bridge_hash", hex.EncodeToString(b.siteBridgePub[SiteA][:3]),
		"siteB_bridge_hash", hex.EncodeToString(b.siteBridgePub[SiteB][:3]),
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

func (b *BridgeEngine) openAckWindowLocked(now time.Time) {
	until := now.Add(time.Duration(b.cfg.AckWindowSecs) * time.Second)
	if until.After(b.ackWindowUntil) {
		b.ackWindowUntil = until
	}
}

type identityMatch struct {
	allowed       bool
	openAckWindow bool
	learnedPubHex string
	learnedName   string
}

func isAckPayload(pkt *meshcore.Packet) bool {
	switch pkt.PayloadType() {
	case meshcore.PayloadTypeAck:
		return true
	case meshcore.PayloadTypeMultiPart:
		mp, err := meshcore.MultiPartFromBytes(pkt.Payload)
		return err == nil && mp.WrappedType == meshcore.PayloadTypeAck
	default:
		return false
	}
}

type channelTier int

const (
	channelTierNone channelTier = iota
	channelTierFullMesh
	channelTierZeroHop
)

// classifyChannel checks whether pkt is a GRP_TXT packet that decrypts and
// authenticates cleanly under bridgedChannels (full-mesh) or zeroHopChannels.
func (b *BridgeEngine) classifyChannel(pkt *meshcore.Packet) (string, channelTier) {
	if pkt.PayloadType() != meshcore.PayloadTypeGrpTxt {
		return "", channelTierNone
	}
	gt, err := meshcore.GroupTextFromBytes(pkt.Payload)
	if err != nil {
		return "", channelTierNone
	}

	b.mu.RLock()
	defer b.mu.RUnlock()

	for _, ch := range b.bridgedChannels {
		if ch.Hash == gt.ChannelHash {
			if _, err := gt.DecryptStruct(ch.PSK); err == nil {
				return ch.Name, channelTierFullMesh
			}
		}
	}
	for _, ch := range b.zeroHopChannels {
		if ch.Hash == gt.ChannelHash {
			if _, err := gt.DecryptStruct(ch.PSK); err == nil {
				return ch.Name, channelTierZeroHop
			}
		}
	}
	return "", channelTierNone
}

// classifyIdentityPacket checks whether pkt is non-channel identity discovery
// or private messaging traffic involving at least one allowlisted companion
// ("whenever either side": src || dst). It never matches PayloadTypeGrpTxt.
func (b *BridgeEngine) classifyIdentityPacket(pkt *meshcore.Packet, now time.Time) identityMatch {
	b.mu.RLock()
	defer b.mu.RUnlock()

	if len(b.companions) == 0 {
		return identityMatch{}
	}

	switch pkt.PayloadType() {
	case meshcore.PayloadTypeAdvert:
		adv, err := meshcore.AdvertFromBytes(pkt.Payload)
		if err != nil || !adv.Verify() {
			return identityMatch{}
		}
		pubBytes := adv.PublicKey.PublicKeyBytes()
		if !b.matchPubKeyLocked(pubBytes) {
			return identityMatch{}
		}
		m := identityMatch{allowed: true}
		appData := adv.AppData()
		if adv.AppDataErr() == nil && appData.Name != "" {
			m.learnedPubHex = hex.EncodeToString(pubBytes)
			m.learnedName = appData.Name
		}
		return m

	case meshcore.PayloadTypeAnonReq:
		if len(pkt.Payload) < 1+meshcore.PubKeySize+2 {
			return identityMatch{}
		}
		destHash := pkt.Payload[0]
		senderPub := pkt.Payload[1 : 1+meshcore.PubKeySize]
		if b.matchPubKeyLocked(senderPub) || b.matchHash1Locked(destHash) {
			return identityMatch{allowed: true, openAckWindow: true}
		}
		return identityMatch{}

	case meshcore.PayloadTypeTxtMsg, meshcore.PayloadTypeReq,
		meshcore.PayloadTypeResponse, meshcore.PayloadTypePath:
		if len(pkt.Payload) < 4 {
			return identityMatch{}
		}
		destHash := pkt.Payload[0]
		srcHash := pkt.Payload[1]
		if b.matchHash1Locked(srcHash) || b.matchHash1Locked(destHash) {
			return identityMatch{allowed: true, openAckWindow: true}
		}
		return identityMatch{}

	case meshcore.PayloadTypeAck:
		return identityMatch{allowed: now.Before(b.ackWindowUntil)}

	case meshcore.PayloadTypeMultiPart:
		mp, err := meshcore.MultiPartFromBytes(pkt.Payload)
		if err == nil && mp.WrappedType == meshcore.PayloadTypeAck {
			return identityMatch{allowed: now.Before(b.ackWindowUntil)}
		}
		return identityMatch{}
	}

	return identityMatch{}
}

func (b *BridgeEngine) applyIdentitySideEffects(m identityMatch, now time.Time) {
	if !m.openAckWindow && m.learnedPubHex == "" {
		return
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	if m.openAckWindow {
		b.openAckWindowLocked(now)
	}
	if m.learnedPubHex != "" && b.learnedNames[m.learnedPubHex] != m.learnedName {
		b.learnedNames[m.learnedPubHex] = m.learnedName
		b.saveLearnedNamesLocked()
		b.log.Info("learned allowlisted companion name from verified ADVERT",
			"pub_key", m.learnedPubHex[:16]+"...", "name", m.learnedName)
	}
}

func (b *BridgeEngine) floodToPeerSite(pkt *meshcore.Packet, fromSite, toSite SiteID) ([]byte, error) {
	clone := pkt.Clone()
	if clone.IsRouteDirect() {
		clone.Header = meshcore.MakeHeader(meshcore.RouteTypeFlood, clone.PayloadType(), clone.PayloadVer())
		clone.TransportCode1, clone.TransportCode2 = 0, 0
	}

	fromRegion := b.siteRegion[fromSite]
	toRegion := b.siteRegion[toSite]

	inDefaultScope := false
	if fromRegion == nil {
		// Source default scope is unscoped ("*").
		inDefaultScope = !clone.IsTransport() || clone.TransportCode1 == 0
	} else {
		// Source default scope is a named region (e.g. "#ioi"); also translate plain unscoped floods.
		inDefaultScope = fromRegion.MatchesPacket(clone) || !clone.IsTransport() || clone.TransportCode1 == 0
	}

	if inDefaultScope && !sameScope(fromRegion, toRegion) {
		clone.SetScope(toRegion)
		b.Counters[fromSite].ScopeTranslated.Add(1)
	}

	// Append both bridge endpoints to Path so remote nodes learn a direct return route back across the bridge.
	srcPub := b.siteBridgePub[fromSite]
	dstPub := b.siteBridgePub[toSite]
	clone.AppendPathHash(srcPub[:])
	clone.AppendPathHash(dstPub[:])

	return clone.ToBytes()
}

func clampZeroHopDirect(pkt *meshcore.Packet) ([]byte, error) {
	clone := pkt.Clone()
	hashSize := pkt.PathHashSize()
	clone.Header = meshcore.MakeHeader(meshcore.RouteTypeDirect, clone.PayloadType(), clone.PayloadVer())
	clone.TransportCode1 = 0
	clone.TransportCode2 = 0
	clone.Path = nil
	clone.PathLength = meshcore.MakePathLen(hashSize, 0)
	return clone.ToBytes()
}

// RoutePacket evaluates raw MeshCore packet bytes received at fromSite and
// returns the rewritten wire bytes to transmit on the peer site (or nil if dropped).
//
// Policy:
//   1. Bridged channels (e.g. #maddub or private PSK channels): full-mesh flood
//      in both directions regardless of hop count or sender.
//   2. Zero-hop channels (e.g. #ireland, #dublin, #madrid — zero city overlap):
//      - Originated locally at 0 hops (PathHashCount == 0, near a site or from OwlShack)
//        -> flooded onto the peer site's mesh (with scope translation) so you can write.
//      - Heard from the mesh via repeaters (PathHashCount > 0)
//        -> clamped to 0-hop ROUTE_TYPE_DIRECT on the peer site so you can read near
//           your site (and on OwlShack) without peer-mesh repeaters re-broadcasting.
//   3. Identity discovery (signed ADVERT of allowlisted companions) and private
//      messages / path discovery where either src or dst matches an allowlisted
//      companion: flood-bridged + direct wormhole return routing.
//   4. Everything else (Public, local hashtag channels, foreign repeater/companion
//      ADVERTs): strictly dropped.
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

	// 1. Direct packets: wormhole return routing OR 0-hop local channel transmission.
	if pkt.IsRouteDirect() {
		if pkt.PathHashCount() >= 2 {
			hashes := pkt.PathHashes()
			hSize := int(pkt.PathHashSize())
			srcPub := b.siteBridgePub[fromSite]
			dstPub := b.siteBridgePub[toSite]
			if bytes.Equal(hashes[0], srcPub[:hSize]) && bytes.Equal(hashes[1], dstPub[:hSize]) {
				clone := pkt.Clone()
				clone.RemoveFirstPathHash()
				clone.RemoveFirstPathHash()
				clone.Header = meshcore.MakeHeader(meshcore.RouteTypeDirect, clone.PayloadType(), clone.PayloadVer())
				clone.TransportCode1, clone.TransportCode2 = 0, 0

				idMatch := b.classifyIdentityPacket(clone, now)
				_, chTier := b.classifyChannel(clone)
				// Direct ACKs explicitly routed through our synthetic bridge pair carry only a
				// 4-byte checksum (no src/dst hash) and were learned from a prior bridged flood.
				if !idMatch.allowed && chTier == channelTierNone && !isAckPayload(clone) {
					b.Counters[fromSite].FilteredDropped.Add(1)
					return nil, ActionFilteredDrop, nil
				}
				if b.hasSeenOrMark(pkt) {
					b.Counters[fromSite].DedupDropped.Add(1)
					return nil, ActionDedupDrop, nil
				}
				b.applyIdentitySideEffects(idMatch, now)

				out, err := clone.ToBytes()
				if err != nil {
					b.Counters[fromSite].InvalidDropped.Add(1)
					return nil, ActionInvalidDrop, err
				}
				b.Counters[fromSite].DirectWormhole.Add(1)
				return out, ActionDirectWormhole, nil
			}
		}

		// A 0-hop direct GRP_TXT sent near this site on a bridged or zero-hop channel
		// floods onto the peer site's mesh.
		if pkt.PathHashCount() == 0 {
			if _, chTier := b.classifyChannel(pkt); chTier != channelTierNone {
				if b.hasSeenOrMark(pkt) {
					b.Counters[fromSite].DedupDropped.Add(1)
					return nil, ActionDedupDrop, nil
				}
				out, err := b.floodToPeerSite(pkt, fromSite, toSite)
				if err != nil {
					b.Counters[fromSite].InvalidDropped.Add(1)
					return nil, ActionInvalidDrop, err
				}
				if chTier == channelTierFullMesh {
					b.Counters[fromSite].ChannelBridged.Add(1)
					return out, ActionChannelBridged, nil
				}
				b.Counters[fromSite].ZeroHopFlood.Add(1)
				return out, ActionZeroHopFlood, nil
			}
		}

		b.Counters[fromSite].FilteredDropped.Add(1)
		return nil, ActionFilteredDrop, nil
	}

	// 2. Flood traffic: full-mesh bridgedChannels, asymmetric zeroHopChannels, or allowlisted identity/DM packets.
	if pkt.IsRouteFlood() && !pkt.IsShare() {
		_, chTier := b.classifyChannel(pkt)
		var idMatch identityMatch
		if chTier == channelTierNone {
			idMatch = b.classifyIdentityPacket(pkt, now)
		}

		if chTier != channelTierNone || idMatch.allowed {
			if int(pkt.PathHashCount()) > b.cfg.MaxFloodHops {
				b.Counters[fromSite].HopLimitDropped.Add(1)
				return nil, ActionHopLimitDrop, nil
			}
			if b.hasSeenOrMark(pkt) {
				b.Counters[fromSite].DedupDropped.Add(1)
				return nil, ActionDedupDrop, nil
			}
			b.applyIdentitySideEffects(idMatch, now)

			switch chTier {
			case channelTierFullMesh:
				out, err := b.floodToPeerSite(pkt, fromSite, toSite)
				if err != nil {
					b.Counters[fromSite].InvalidDropped.Add(1)
					return nil, ActionInvalidDrop, err
				}
				b.Counters[fromSite].ChannelBridged.Add(1)
				return out, ActionChannelBridged, nil

			case channelTierZeroHop:
				if pkt.PathHashCount() == 0 {
					out, err := b.floodToPeerSite(pkt, fromSite, toSite)
					if err != nil {
						b.Counters[fromSite].InvalidDropped.Add(1)
						return nil, ActionInvalidDrop, err
					}
					b.Counters[fromSite].ZeroHopFlood.Add(1)
					return out, ActionZeroHopFlood, nil
				}
				out, err := clampZeroHopDirect(pkt)
				if err != nil {
					b.Counters[fromSite].InvalidDropped.Add(1)
					return nil, ActionInvalidDrop, err
				}
				b.Counters[fromSite].ZeroHopClamped.Add(1)
				return out, ActionZeroHopClamped, nil

			default:
				out, err := b.floodToPeerSite(pkt, fromSite, toSite)
				if err != nil {
					b.Counters[fromSite].InvalidDropped.Add(1)
					return nil, ActionInvalidDrop, err
				}
				b.Counters[fromSite].IdentityBridged.Add(1)
				return out, ActionIdentityBridged, nil
			}
		}
	}

	// 3. Non-matching traffic stays strictly on its own mesh and OwlShack instance.
	b.Counters[fromSite].FilteredDropped.Add(1)
	return nil, ActionFilteredDrop, nil
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
