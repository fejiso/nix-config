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
	SiteUnspecified SiteID = -1
	SiteA           SiteID = 0
	SiteB           SiteID = 1
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

type zeroHopEntry struct {
	ch       *meshcore.ChannelEntry
	homeSite SiteID // SiteA, SiteB, or SiteUnspecified
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
	AdvertsSent     atomic.Uint64
}

type persistedIdentities struct {
	SiteAPubHex  string `json:"siteAPubHex"`
	SiteASeedHex string `json:"siteASeedHex,omitempty"`
	SiteBPubHex  string `json:"siteBPubHex"`
	SiteBSeedHex string `json:"siteBSeedHex,omitempty"`
}

type persistedAdvertState struct {
	LastDirectUnix [2]int64 `json:"lastDirectUnix"`
	LastFloodUnix  [2]int64 `json:"lastFloodUnix"`
}

type BridgeEngine struct {
	cfg *Config
	log *slog.Logger

	siteRegion    [2]*meshcore.Region
	siteBridgeID  [2]meshcore.LocalIdentity
	siteBridgePub [2][meshcore.PubKeySize]byte
	hasBridgeKeys bool

	advertMu    sync.Mutex
	advertState persistedAdvertState

	mu              sync.RWMutex
	companions      []parsedCompanion
	bridgedChannels []*meshcore.ChannelEntry
	zeroHopChannels []zeroHopEntry
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

func generateBridgeIdentity(avoidFirstByte int) (meshcore.LocalIdentity, [ed25519.SeedSize]byte, error) {
	var seed [ed25519.SeedSize]byte
	for range 256 {
		if _, err := rand.Read(seed[:]); err != nil {
			return meshcore.LocalIdentity{}, seed, err
		}
		id := meshcore.NewLocalIdentityFromSeed(seed)
		pub := id.PublicKey()
		if pub[0] == 0x00 || pub[0] == 0xFF || int(pub[0]) == avoidFirstByte {
			continue
		}
		return id, seed, nil
	}
	return meshcore.LocalIdentity{}, seed, fmt.Errorf("failed to generate valid bridge identity")
}

func (b *BridgeEngine) initPersistence() error {
	hadLegacyPubOnly := false
	if b.cfg.StateDir != "" {
		if err := os.MkdirAll(b.cfg.StateDir, 0o750); err != nil {
			return fmt.Errorf("mkdir stateDir %s: %w", b.cfg.StateDir, err)
		}
		idPath := filepath.Join(b.cfg.StateDir, "bridge_identities.json")
		if raw, err := os.ReadFile(idPath); err == nil {
			var p persistedIdentities
			if json.Unmarshal(raw, &p) == nil {
				seedA, errSA := hex.DecodeString(p.SiteASeedHex)
				seedB, errSB := hex.DecodeString(p.SiteBSeedHex)
				if errSA == nil && errSB == nil && len(seedA) == ed25519.SeedSize && len(seedB) == ed25519.SeedSize {
					var arrA, arrB [ed25519.SeedSize]byte
					copy(arrA[:], seedA)
					copy(arrB[:], seedB)
					b.siteBridgeID[SiteA] = meshcore.NewLocalIdentityFromSeed(arrA)
					b.siteBridgeID[SiteB] = meshcore.NewLocalIdentityFromSeed(arrB)
					b.siteBridgePub[SiteA] = b.siteBridgeID[SiteA].PublicKey()
					b.siteBridgePub[SiteB] = b.siteBridgeID[SiteB].PublicKey()
					b.hasBridgeKeys = true
				} else if p.SiteAPubHex != "" || p.SiteBPubHex != "" {
					hadLegacyPubOnly = true
				}
			}
		}

		namesPath := filepath.Join(b.cfg.StateDir, "learned_names.json")
		if raw, err := os.ReadFile(namesPath); err == nil {
			_ = json.Unmarshal(raw, &b.learnedNames)
		}

		advPath := filepath.Join(b.cfg.StateDir, "advert_state.json")
		if raw, err := os.ReadFile(advPath); err == nil {
			_ = json.Unmarshal(raw, &b.advertState)
		}
	}

	if !b.hasBridgeKeys {
		idA, seedA, err := generateBridgeIdentity(-1)
		if err != nil {
			return err
		}
		idB, seedB, err := generateBridgeIdentity(int(idA.PublicKey()[0]))
		if err != nil {
			return err
		}
		b.siteBridgeID[SiteA] = idA
		b.siteBridgeID[SiteB] = idB
		b.siteBridgePub[SiteA] = idA.PublicKey()
		b.siteBridgePub[SiteB] = idB.PublicKey()
		b.hasBridgeKeys = true

		if hadLegacyPubOnly {
			b.log.Info("upgraded legacy pubkey-only bridge_identities.json to full Ed25519 signing identities",
				"siteA_hash", hex.EncodeToString(b.siteBridgePub[SiteA][:3]),
				"siteB_hash", hex.EncodeToString(b.siteBridgePub[SiteB][:3]),
			)
		}

		if b.cfg.StateDir != "" {
			idPath := filepath.Join(b.cfg.StateDir, "bridge_identities.json")
			raw, _ := json.MarshalIndent(persistedIdentities{
				SiteAPubHex:  hex.EncodeToString(b.siteBridgePub[SiteA][:]),
				SiteASeedHex: hex.EncodeToString(seedA[:]),
				SiteBPubHex:  hex.EncodeToString(b.siteBridgePub[SiteB][:]),
				SiteBSeedHex: hex.EncodeToString(seedB[:]),
			}, "", "  ")
			_ = os.WriteFile(idPath, raw, 0o600)
		}
	}
	return nil
}

func (b *BridgeEngine) saveAdvertStateLocked() {
	if b.cfg.StateDir == "" {
		return
	}
	advPath := filepath.Join(b.cfg.StateDir, "advert_state.json")
	if raw, err := json.MarshalIndent(b.advertState, "", "  "); err == nil {
		_ = os.WriteFile(advPath, raw, 0o640)
	}
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

func (b *BridgeEngine) siteConfig(s SiteID) SiteConfig {
	if s == SiteA {
		return b.cfg.SiteA
	}
	return b.cfg.SiteB
}

// BuildSiteAdvert constructs a signed REPEATER ADVERT packet for the tunnel
// endpoint at site (either 0-hop DIRECT or scoped FLOOD matching the site's
// defaultScope and pathHashSize).
func (b *BridgeEngine) BuildSiteAdvert(site SiteID, flood bool, now time.Time) ([]byte, error) {
	sc := b.siteConfig(site)
	name := strings.TrimSpace(sc.AdvertName)
	if name == "" {
		return nil, fmt.Errorf("site %s advertName is empty", sc.Name)
	}
	hashSize := sc.PathHashSize
	if hashSize < 1 || hashSize > 3 {
		hashSize = 3
	}

	adv, err := meshcore.NewAdvert(b.siteBridgeID[site], meshcore.AdvertAppData{
		Type: "REPEATER",
		Name: name,
	}, uint32(now.Unix()))
	if err != nil {
		return nil, err
	}
	advBytes, err := adv.ToBytes()
	if err != nil {
		return nil, err
	}

	routeType := meshcore.RouteTypeDirect
	if flood {
		routeType = meshcore.RouteTypeFlood
	}
	pkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(routeType, meshcore.PayloadTypeAdvert, 0),
		PathLength: meshcore.MakePathLen(hashSize, 0),
		Payload:    advBytes,
	}
	if flood && b.siteRegion[site] != nil {
		pkt.SetScope(b.siteRegion[site])
	}

	raw, err := pkt.ToBytes()
	if err != nil {
		return nil, err
	}
	_ = b.hasSeenOrMark(pkt)
	return raw, nil
}

// CheckDueSiteAdvert checks whether site should transmit a periodic FLOOD or
// 0-hop DIRECT tunnel REPEATER advert at now. On the first connection of a
// process (sentStartup == false), it emits a 0-hop DIRECT advert if no FLOOD
// advert is due so local OwlShack and nearby companions resolve the tunnel hop
// immediately without spamming the wider mesh across restarts.
func (b *BridgeEngine) CheckDueSiteAdvert(site SiteID, sentStartup bool, now time.Time) ([]byte, bool, error) {
	sc := b.siteConfig(site)
	if strings.TrimSpace(sc.AdvertName) == "" {
		return nil, false, nil
	}

	directMins := sc.DirectAdvertMins
	floodMins := sc.FloodAdvertMins
	if directMins == 0 && floodMins == 0 {
		directMins = 120
		floodMins = 720
	}

	b.advertMu.Lock()
	lastDirect := b.advertState.LastDirectUnix[site]
	lastFlood := b.advertState.LastFloodUnix[site]
	b.advertMu.Unlock()

	nowUnix := now.Unix()
	if floodMins > 0 && (lastFlood == 0 || nowUnix-lastFlood >= int64(floodMins)*60) {
		raw, err := b.BuildSiteAdvert(site, true, now)
		return raw, true, err
	}
	if directMins > 0 && (!sentStartup || lastDirect == 0 || nowUnix-lastDirect >= int64(directMins)*60) {
		raw, err := b.BuildSiteAdvert(site, false, now)
		return raw, false, err
	}
	return nil, false, nil
}

func (b *BridgeEngine) MarkSiteAdvertSent(site SiteID, wasFlood bool, now time.Time) {
	b.advertMu.Lock()
	nowUnix := now.Unix()
	b.advertState.LastDirectUnix[site] = nowUnix
	if wasFlood {
		b.advertState.LastFloodUnix[site] = nowUnix
	}
	b.saveAdvertStateLocked()
	b.advertMu.Unlock()
	b.Counters[site].AdvertsSent.Add(1)
}

func parseSingleChannel(label string, cc ChannelConfig) (*meshcore.ChannelEntry, string, string, error) {
	name := strings.TrimSpace(cc.Name)
	if name == "" || name == "*" {
		return nil, "", "", nil
	}
	psk := strings.TrimSpace(cc.PSKBase64)
	if psk != "" {
		ch, err := meshcore.NewChannelFromBase64(name, psk)
		if err != nil {
			return nil, "", "", fmt.Errorf("%s %q PSK: %w", label, name, err)
		}
		return ch, name, name + "\x00" + psk, nil
	}
	if strings.EqualFold(name, "Public") {
		return meshcore.PublicChannel(), "Public", "Public", nil
	}
	norm := meshcore.NormalizeHashtag(name)
	return meshcore.NewChannelFromHashtag(norm), norm, norm, nil
}

func parseChannelConfigs(label string, chConfigs []ChannelConfig) ([]*meshcore.ChannelEntry, []string, error) {
	var out []*meshcore.ChannelEntry
	seen := map[string]bool{}
	var names []string

	for _, cc := range chConfigs {
		ch, dispName, key, err := parseSingleChannel(label, cc)
		if err != nil {
			return nil, nil, err
		}
		if ch == nil || seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, ch)
		names = append(names, dispName)
	}
	return out, names, nil
}

func (b *BridgeEngine) resolveHomeSite(home string) (SiteID, error) {
	home = strings.TrimSpace(home)
	if home == "" {
		return SiteUnspecified, nil
	}
	if strings.EqualFold(home, b.cfg.SiteA.Name) {
		return SiteA, nil
	}
	if strings.EqualFold(home, b.cfg.SiteB.Name) {
		return SiteB, nil
	}
	return SiteUnspecified, fmt.Errorf("unknown homeSite %q (expected %q or %q)", home, b.cfg.SiteA.Name, b.cfg.SiteB.Name)
}

func (b *BridgeEngine) parseZeroHopConfigs(chConfigs []ChannelConfig) ([]zeroHopEntry, []string, error) {
	var out []zeroHopEntry
	seenIdx := map[string]int{}
	var names []string

	for _, cc := range chConfigs {
		ch, dispName, key, err := parseSingleChannel("zeroHopChannel", cc)
		if err != nil {
			return nil, nil, err
		}
		if ch == nil {
			continue
		}
		hs, err := b.resolveHomeSite(cc.HomeSite)
		if err != nil {
			return nil, nil, fmt.Errorf("zeroHopChannel %q: %w", dispName, err)
		}
		if idx, exists := seenIdx[key]; exists {
			if out[idx].homeSite == SiteUnspecified && hs != SiteUnspecified {
				out[idx].homeSite = hs
			}
			continue
		}
		seenIdx[key] = len(out)
		out = append(out, zeroHopEntry{ch: ch, homeSite: hs})
		if hs != SiteUnspecified {
			siteLabel := b.cfg.SiteA.Name
			if hs == SiteB {
				siteLabel = b.cfg.SiteB.Name
			}
			names = append(names, fmt.Sprintf("%s@%s", dispName, siteLabel))
		} else {
			names = append(names, dispName)
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
	seenComp := map[string]int{}
	for _, e := range entries {
		clean := strings.TrimPrefix(strings.TrimSpace(e.PubKey), "0x")
		if clean == "" {
			continue
		}
		decoded, err := hex.DecodeString(clean)
		if err != nil || len(decoded) == 0 || len(decoded) > meshcore.PubKeySize {
			return fmt.Errorf("invalid companion pubKey %q: must be 2..64 hex chars", e.PubKey)
		}
		name := strings.TrimSpace(e.Name)
		dedupKey := hex.EncodeToString(decoded) + "\x00" + name
		if len(decoded) >= 4 {
			// Full/long pubkey prefixes uniquely identify the companion; merge optional display name.
			dedupKey = hex.EncodeToString(decoded)
		}
		if idx, exists := seenComp[dedupKey]; exists {
			if parsed[idx].name == "" && name != "" {
				parsed[idx].name = name
			}
			continue
		}
		seenComp[dedupKey] = len(parsed)
		parsed = append(parsed, parsedCompanion{
			keyPrefix: decoded,
			name:      name,
		})
	}

	bridgedChannels, bridgedNames, err := parseChannelConfigs("bridgedChannel", bridgedCfgs)
	if err != nil {
		return err
	}
	zeroHopChannels, zeroHopNames, err := b.parseZeroHopConfigs(zeroHopCfgs)
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

// pinnedFullKeyHexLocked returns the learned 64-hex-char public key for a
// short-prefix companion with a configured display name, if previously verified
// via a signed ADVERT.
func (b *BridgeEngine) pinnedFullKeyHexLocked(c parsedCompanion) string {
	if c.name == "" {
		return ""
	}
	for pubHex, learnedName := range b.learnedNames {
		if learnedName != c.name {
			continue
		}
		if raw, err := hex.DecodeString(pubHex); err == nil && len(raw) >= len(c.keyPrefix) && bytes.Equal(raw[:len(c.keyPrefix)], c.keyPrefix) {
			return pubHex
		}
	}
	return ""
}

// matchAdvertLocked checks whether a verified ADVERT public key + name matches
// an allowlisted companion. Short prefixes (< 4 bytes) paired with a configured
// display name require either a previously pinned full key or an exact name
// match so unrelated repeaters sharing a 1-byte prefix are never bridged.
func (b *BridgeEngine) matchAdvertLocked(pubKey []byte, advName string) bool {
	pubHex := ""
	for _, c := range b.companions {
		if len(pubKey) < len(c.keyPrefix) || !bytes.Equal(pubKey[:len(c.keyPrefix)], c.keyPrefix) {
			continue
		}
		if len(c.keyPrefix) >= 4 || c.name == "" {
			return true
		}
		if pubHex == "" {
			pubHex = hex.EncodeToString(pubKey)
		}
		if pinned := b.pinnedFullKeyHexLocked(c); pinned != "" {
			if pubHex == pinned {
				return true
			}
			continue
		}
		if advName != "" && advName == c.name {
			return true
		}
	}
	return false
}

// matchPubKeyLocked checks a 32-byte sender public key on ANON_REQ packets.
func (b *BridgeEngine) matchPubKeyLocked(pubKey []byte) bool {
	pubHex := ""
	for _, c := range b.companions {
		if len(pubKey) < len(c.keyPrefix) || !bytes.Equal(pubKey[:len(c.keyPrefix)], c.keyPrefix) {
			continue
		}
		if len(c.keyPrefix) >= 4 || c.name == "" {
			return true
		}
		if pinned := b.pinnedFullKeyHexLocked(c); pinned != "" {
			if pubHex == "" {
				pubHex = hex.EncodeToString(pubKey)
			}
			if pubHex == pinned {
				return true
			}
			continue
		}
		return true
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

func (b *BridgeEngine) matchCompanionSender(sender string) bool {
	if sender == "" {
		return false
	}
	b.mu.RLock()
	defer b.mu.RUnlock()
	for _, c := range b.companions {
		if c.name != "" && c.name == sender {
			return true
		}
	}
	for pubHex, learnedName := range b.learnedNames {
		if learnedName != sender {
			continue
		}
		if raw, err := hex.DecodeString(pubHex); err == nil && b.matchAdvertLocked(raw, learnedName) {
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

type channelMatch struct {
	tier     channelTier
	name     string
	sender   string
	homeSite SiteID
}

// classifyChannel checks whether pkt is a GRP_TXT packet that decrypts and
// authenticates cleanly under bridgedChannels (full-mesh) or zeroHopChannels.
func (b *BridgeEngine) classifyChannel(pkt *meshcore.Packet) channelMatch {
	if pkt.PayloadType() != meshcore.PayloadTypeGrpTxt {
		return channelMatch{}
	}
	gt, err := meshcore.GroupTextFromBytes(pkt.Payload)
	if err != nil {
		return channelMatch{}
	}

	b.mu.RLock()
	defer b.mu.RUnlock()

	for _, ch := range b.bridgedChannels {
		if ch.Hash == gt.ChannelHash {
			if msg, err := gt.DecryptStruct(ch.PSK); err == nil {
				return channelMatch{
					tier:     channelTierFullMesh,
					name:     ch.Name,
					sender:   msg.Sender,
					homeSite: SiteUnspecified,
				}
			}
		}
	}
	for _, ze := range b.zeroHopChannels {
		if ze.ch.Hash == gt.ChannelHash {
			if msg, err := gt.DecryptStruct(ze.ch.PSK); err == nil {
				return channelMatch{
					tier:     channelTierZeroHop,
					name:     ze.ch.Name,
					sender:   msg.Sender,
					homeSite: ze.homeSite,
				}
			}
		}
	}
	return channelMatch{}
}

// shouldFloodZeroHop decides whether a zeroHopChannel packet received at fromSite
// should flood onto the peer site's mesh (write) or clamp to 0-hop DIRECT (read).
//
//   - When homeSite is configured (e.g. #madrid -> pinto, #ireland/#dublin -> dublin):
//     any transmission heard at the away site (fromSite != homeSite, whether 0-hop or
//     relayed across local repeaters such as DUB-DUNDRUM-solarbird) floods onto
//     homeSite's mesh, while traffic heard on homeSite clamps to 0-hop DIRECT at the
//     peer site so OwlShack and nearby companions can read without cross-country spam.
//   - When homeSite is unset: 0-hop transmissions or messages sent by an allowlisted
//     companion name flood; multi-hop mesh chatter from unknown senders clamps.
func (b *BridgeEngine) shouldFloodZeroHop(pkt *meshcore.Packet, fromSite SiteID, cm channelMatch) bool {
	if cm.homeSite != SiteUnspecified {
		return fromSite != cm.homeSite
	}
	return pkt.PathHashCount() == 0 || b.matchCompanionSender(cm.sender)
}

// hasBridgePathPair reports whether pkt's flood Path already contains our
// synthetic [siteA, siteB] or [siteB, siteA] bridge hop pair, preventing
// long-delayed multi-hop mesh echoes (or bit-corrupted repeats) from ever
// ping-ponging back across the bridge.
func (b *BridgeEngine) hasBridgePathPair(pkt *meshcore.Packet) bool {
	if pkt.PathHashCount() < 2 {
		return false
	}
	hashes := pkt.PathHashes()
	hSize := int(pkt.PathHashSize())
	if hSize <= 0 || hSize > meshcore.PubKeySize {
		return false
	}
	pubA := b.siteBridgePub[SiteA][:hSize]
	pubB := b.siteBridgePub[SiteB][:hSize]
	for i := 0; i+1 < len(hashes); i++ {
		if (bytes.Equal(hashes[i], pubA) && bytes.Equal(hashes[i+1], pubB)) ||
			(bytes.Equal(hashes[i], pubB) && bytes.Equal(hashes[i+1], pubA)) {
			return true
		}
	}
	return false
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
		advName := ""
		appData := adv.AppData()
		if adv.AppDataErr() == nil {
			advName = appData.Name
		}
		if !b.matchAdvertLocked(pubBytes, advName) {
			return identityMatch{}
		}
		m := identityMatch{allowed: true}
		if advName != "" {
			m.learnedPubHex = hex.EncodeToString(pubBytes)
			m.learnedName = advName
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
//   2. Zero-hop channels (e.g. #ireland@dublin, #dublin@dublin, #madrid@pinto):
//      - Heard at the away site (fromSite != homeSite, or 0-hop / allowlisted sender
//        when homeSite is unset) -> flooded onto the target mesh (with scope translation).
//      - Heard on the channel's home mesh -> clamped to 0-hop ROUTE_TYPE_DIRECT on
//        the peer site so you can read locally without repeater re-broadcast.
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
				cm := b.classifyChannel(clone)
				// Direct ACKs explicitly routed through our synthetic bridge pair carry only a
				// 4-byte checksum (no src/dst hash) and were learned from a prior bridged flood.
				if !idMatch.allowed && cm.tier == channelTierNone && !isAckPayload(clone) {
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

		// A 0-hop direct GRP_TXT sent near this site on a bridged or zero-hop channel.
		if pkt.PathHashCount() == 0 {
			if cm := b.classifyChannel(pkt); cm.tier != channelTierNone {
				if b.hasSeenOrMark(pkt) {
					b.Counters[fromSite].DedupDropped.Add(1)
					return nil, ActionDedupDrop, nil
				}
				if cm.tier == channelTierFullMesh {
					out, err := b.floodToPeerSite(pkt, fromSite, toSite)
					if err != nil {
						b.Counters[fromSite].InvalidDropped.Add(1)
						return nil, ActionInvalidDrop, err
					}
					b.Counters[fromSite].ChannelBridged.Add(1)
					return out, ActionChannelBridged, nil
				}
				if b.shouldFloodZeroHop(pkt, fromSite, cm) {
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
			}
		}

		b.Counters[fromSite].FilteredDropped.Add(1)
		return nil, ActionFilteredDrop, nil
	}

	// 2. Flood traffic: full-mesh bridgedChannels, asymmetric zeroHopChannels, or allowlisted identity/DM packets.
	if pkt.IsRouteFlood() && !pkt.IsShare() {
		cm := b.classifyChannel(pkt)
		var idMatch identityMatch
		if cm.tier == channelTierNone {
			idMatch = b.classifyIdentityPacket(pkt, now)
		}

		if cm.tier != channelTierNone || idMatch.allowed {
			if b.hasBridgePathPair(pkt) {
				b.Counters[fromSite].DedupDropped.Add(1)
				return nil, ActionDedupDrop, nil
			}
			if int(pkt.PathHashCount()) > b.cfg.MaxFloodHops {
				b.Counters[fromSite].HopLimitDropped.Add(1)
				return nil, ActionHopLimitDrop, nil
			}
			if b.hasSeenOrMark(pkt) {
				b.Counters[fromSite].DedupDropped.Add(1)
				return nil, ActionDedupDrop, nil
			}
			b.applyIdentitySideEffects(idMatch, now)

			switch cm.tier {
			case channelTierFullMesh:
				out, err := b.floodToPeerSite(pkt, fromSite, toSite)
				if err != nil {
					b.Counters[fromSite].InvalidDropped.Add(1)
					return nil, ActionInvalidDrop, err
				}
				b.Counters[fromSite].ChannelBridged.Add(1)
				return out, ActionChannelBridged, nil

			case channelTierZeroHop:
				if b.shouldFloodZeroHop(pkt, fromSite, cm) {
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
