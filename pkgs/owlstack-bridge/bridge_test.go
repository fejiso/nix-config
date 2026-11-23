package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"net"
	"os"
	"path/filepath"
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
		BridgedChannels: []ChannelConfig{
			{Name: "#maddub"},
		},
		ZeroHopChannels: []ChannelConfig{
			{Name: "#ireland"},
			{Name: "#dublin"},
			{Name: "#madrid"},
		},
		SiteA: SiteConfig{
			Name:         "pinto",
			RemoteAddr:   "127.0.0.1:19001",
			DefaultScope: "*",
			FreqMHz:      869.608,
			BwKHz:        62.5,
			SF:           8,
			CR:           8,
			TxPower:      20,
		},
		SiteB: SiteConfig{
			Name:         "dublin",
			RemoteAddr:   "127.0.0.1:19002",
			DefaultScope: "#ioi",
			FreqMHz:      869.602,
			BwKHz:        62.5,
			SF:           8,
			CR:           8,
			TxPower:      20,
		},
	}
}

func makeIdentityWithPrefix(t *testing.T, avoid ...byte) meshcore.LocalIdentity {
	t.Helper()
	avoidSet := map[byte]bool{0x00: true, 0xFF: true}
	for _, b := range avoid {
		avoidSet[b] = true
	}
	for range 512 {
		id, err := meshcore.GenerateLocalIdentity(rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		pk := id.PublicKey()
		if !avoidSet[pk[0]] {
			return id
		}
	}
	t.Fatal("could not generate distinct identity")
	return meshcore.LocalIdentity{}
}

func TestCleanSplitIdentityAndChannelPolicy(t *testing.T) {
	allowedID := makeIdentityWithPrefix(t)
	strangerID := makeIdentityWithPrefix(t, allowedID.PublicKey()[0])
	otherStrangerID := makeIdentityWithPrefix(t, allowedID.PublicKey()[0], strangerID.PublicKey()[0])

	var privPSK [16]byte
	if _, err := rand.Read(privPSK[:]); err != nil {
		t.Fatal(err)
	}
	privPSKB64 := base64.StdEncoding.EncodeToString(privPSK[:])

	allowedPK := allowedID.PublicKey()
	cfg := newTestConfig(t, hex.EncodeToString(allowedPK[:]))
	cfg.BridgedChannels = append(cfg.BridgedChannels, ChannelConfig{
		Name:      "secret-ops",
		PSKBase64: privPSKB64,
	})
	eng, err := NewBridgeEngine(cfg, nil)
	if err != nil {
		t.Fatal(err)
	}

	now := time.Now()
	ioi := meshcore.NewRegion("#ioi")

	// 1. Allowlisted companion sends unscoped ADVERT in Pinto -> floods into Dublin with #ioi scope.
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
		PathLength: meshcore.MakePathLen(3, 1),
		Path:       []byte{0x42, 0x43, 0x44},
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
	if action != ActionIdentityBridged {
		t.Fatalf("expected ActionIdentityBridged, got %s", action)
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
	if pktOut.PathHashCount() != 3 || pktOut.PathHashSize() != 3 {
		t.Fatalf("expected 3 path hops of 3 bytes (1 + 2 bridge), got count=%d size=%d", pktOut.PathHashCount(), pktOut.PathHashSize())
	}

	// 2. Echo of the bridged packet heard back on Dublin RF -> dedup-dropped.
	echoOut, echoAction, err := eng.RoutePacket(rawOut, SiteB, now)
	if err != nil {
		t.Fatal(err)
	}
	if echoOut != nil || echoAction != ActionDedupDrop {
		t.Fatalf("expected echo to be dedup-dropped, got %s", echoAction)
	}

	// 3. Non-allowlisted stranger ADVERT in Dublin (#ioi) -> strictly dropped (NO 0-hop bleed).
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
		PathLength: meshcore.MakePathLen(3, 1),
		Path:       []byte{0xAA, 0xBB, 0xCC},
		Payload:    strangerBytes,
	}
	strangerPkt.SetScope(ioi)
	strangerRaw, _ := strangerPkt.ToBytes()

	droppedRaw, droppedAct, err := eng.RoutePacket(strangerRaw, SiteB, now)
	if err != nil {
		t.Fatal(err)
	}
	if droppedRaw != nil || droppedAct != ActionFilteredDrop {
		t.Fatalf("expected stranger ADVERT to be filtered_drop with nil out, got act=%s len=%d", droppedAct, len(droppedRaw))
	}

	// 4. GRP_TXT on Public (even from allowlisted "FerMobile"!) -> strictly dropped.
	pubCh := meshcore.PublicChannel()
	pubPayload := &meshcore.GroupTextPayload{
		Timestamp: uint32(now.Unix()) + 2,
		Sender:    "FerMobile",
		Text:      "local public chat stays local",
	}
	pubEnc, err := pubPayload.Encrypt(pubCh.Hash, pubCh.PSK)
	if err != nil {
		t.Fatal(err)
	}
	pubBytes, _ := pubEnc.ToBytes()
	pubPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeGrpTxt, 0),
		PathLength: meshcore.MakePathLen(3, 0),
		Payload:    pubBytes,
	}
	pubPkt.SetScope(ioi)
	pubRaw, _ := pubPkt.ToBytes()

	pubOut, pubAct, err := eng.RoutePacket(pubRaw, SiteB, now)
	if err != nil {
		t.Fatal(err)
	}
	if pubOut != nil || pubAct != ActionFilteredDrop {
		t.Fatalf("expected Public GRP_TXT to be filtered_drop, got act=%s", pubAct)
	}

	// 5. GRP_TXT on #maddub from ANY sender (unknown stranger, no prior ADVERT) -> full-mesh bridged!
	maddubCh := meshcore.NewChannelFromHashtag("#maddub")
	madPayload := &meshcore.GroupTextPayload{
		Timestamp: uint32(now.Unix()) + 3,
		Sender:    "AnyoneInDublin",
		Text:      "hello madrid from #maddub",
	}
	madEnc, err := madPayload.Encrypt(maddubCh.Hash, maddubCh.PSK)
	if err != nil {
		t.Fatal(err)
	}
	madBytes, _ := madEnc.ToBytes()
	madPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeGrpTxt, 0),
		PathLength: meshcore.MakePathLen(3, 0),
		Payload:    madBytes,
	}
	madPkt.SetScope(ioi)
	madRaw, _ := madPkt.ToBytes()

	madOutRaw, madAct, err := eng.RoutePacket(madRaw, SiteB, now)
	if err != nil {
		t.Fatal(err)
	}
	if madAct != ActionChannelBridged {
		t.Fatalf("expected #maddub GRP_TXT to be ActionChannelBridged, got %s", madAct)
	}
	madOutPkt, _ := meshcore.PacketFromBytes(madOutRaw)
	if madOutPkt.RouteType() != meshcore.RouteTypeFlood || madOutPkt.IsTransport() {
		t.Fatalf("expected Dublin #ioi -> Pinto unscoped RouteTypeFlood, got %s", madOutPkt.RouteTypeString())
	}

	// 6. GRP_TXT on custom PSK private channel ("secret-ops") Pinto -> Dublin -> full-mesh bridged with #ioi scope!
	privCh, err := meshcore.NewChannelFromBase64("secret-ops", privPSKB64)
	if err != nil {
		t.Fatal(err)
	}
	privPayload := &meshcore.GroupTextPayload{
		Timestamp: uint32(now.Unix()) + 4,
		Sender:    "punctumatic",
		Text:      "private bridged message",
	}
	privEnc, err := privPayload.Encrypt(privCh.Hash, privCh.PSK)
	if err != nil {
		t.Fatal(err)
	}
	privBytes, _ := privEnc.ToBytes()
	privPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeGrpTxt, 0),
		PathLength: meshcore.MakePathLen(3, 0),
		Payload:    privBytes,
	}
	privRaw, _ := privPkt.ToBytes()

	privOutRaw, privAct, err := eng.RoutePacket(privRaw, SiteA, now)
	if err != nil {
		t.Fatal(err)
	}
	if privAct != ActionChannelBridged {
		t.Fatalf("expected private channel GRP_TXT to be ActionChannelBridged, got %s", privAct)
	}
	privOutPkt, _ := meshcore.PacketFromBytes(privOutRaw)
	if !ioi.MatchesPacket(privOutPkt) {
		t.Fatalf("expected Pinto -> Dublin private channel flood to receive #ioi scope")
	}

	// 7. DM ("whenever either side": src || dst):
	// 7a. Stranger -> Stranger DM is dropped.
	s2sPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeTxtMsg, 0),
		PathLength: meshcore.MakePathLen(3, 0),
		Payload:    []byte{strangerID.PublicKey()[0], otherStrangerID.PublicKey()[0], 1, 2, 3, 4},
	}
	s2sRaw, _ := s2sPkt.ToBytes()
	if out, act, _ := eng.RoutePacket(s2sRaw, SiteA, now); out != nil || act != ActionFilteredDrop {
		t.Fatalf("expected stranger->stranger DM to be dropped, got %s", act)
	}

	// 7b. Allowed -> Stranger DM is bridged AND opens ACK window.
	a2sPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeTxtMsg, 0),
		PathLength: meshcore.MakePathLen(3, 0),
		Payload:    []byte{strangerID.PublicKey()[0], allowedPK[0], 5, 6, 7, 8},
	}
	a2sRaw, _ := a2sPkt.ToBytes()
	if out, act, _ := eng.RoutePacket(a2sRaw, SiteA, now); out == nil || act != ActionIdentityBridged {
		t.Fatalf("expected allowed->stranger DM to bridge, got %s", act)
	}

	// 7c. Stranger -> Allowed DM is ALSO bridged ("whenever either side").
	s2aPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeTxtMsg, 0),
		PathLength: meshcore.MakePathLen(3, 0),
		Payload:    []byte{allowedPK[0], strangerID.PublicKey()[0], 9, 10, 11, 12},
	}
	s2aPkt.SetScope(ioi)
	s2aRaw, _ := s2aPkt.ToBytes()
	if out, act, _ := eng.RoutePacket(s2aRaw, SiteB, now); out == nil || act != ActionIdentityBridged {
		t.Fatalf("expected stranger->allowed DM to bridge, got %s", act)
	}

	// 7d. Flood ACK within opened ACK window is bridged.
	ackPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeAck, 0),
		PathLength: meshcore.MakePathLen(3, 0),
		Payload:    []byte{0xDE, 0xAD, 0xBE, 0xEF},
	}
	ackRaw, _ := ackPkt.ToBytes()
	if out, act, _ := eng.RoutePacket(ackRaw, SiteB, now.Add(5*time.Second)); out == nil || act != ActionIdentityBridged {
		t.Fatalf("expected flood ACK inside window to bridge, got %s", act)
	}
}

func TestZeroHopChannelsReadAndWrite(t *testing.T) {
	allowedID := makeIdentityWithPrefix(t)
	allowedPK := allowedID.PublicKey()

	cfg := newTestConfig(t, hex.EncodeToString(allowedPK[:]))
	eng, err := NewBridgeEngine(cfg, nil)
	if err != nil {
		t.Fatal(err)
	}

	now := time.Now()
	ioi := meshcore.NewRegion("#ioi")
	irelandCh := meshcore.NewChannelFromHashtag("#ireland")
	madridCh := meshcore.NewChannelFromHashtag("#madrid")

	// 1. READ #ireland while near Pinto: mesh flood in Dublin (1 repeater hop) -> clamped to 0-hop DIRECT in Pinto!
	inMsg := &meshcore.GroupTextPayload{
		Timestamp: uint32(now.Unix()) + 10,
		Sender:    "DublinLocal",
		Text:      "anybody in #ireland?",
	}
	inEnc, err := inMsg.Encrypt(irelandCh.Hash, irelandCh.PSK)
	if err != nil {
		t.Fatal(err)
	}
	inBytes, _ := inEnc.ToBytes()
	inPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeGrpTxt, 0),
		PathLength: meshcore.MakePathLen(3, 1),
		Path:       []byte{0x24, 0x41, 0xf6}, // 1 repeater hop in Dublin
		Payload:    inBytes,
	}
	inPkt.SetScope(ioi)
	inRaw, _ := inPkt.ToBytes()

	readOutRaw, readAct, err := eng.RoutePacket(inRaw, SiteB, now)
	if err != nil {
		t.Fatal(err)
	}
	if readAct != ActionZeroHopClamped {
		t.Fatalf("expected ActionZeroHopClamped for mesh #ireland flood, got %s", readAct)
	}
	readOutPkt, err := meshcore.PacketFromBytes(readOutRaw)
	if err != nil {
		t.Fatal(err)
	}
	if readOutPkt.RouteType() != meshcore.RouteTypeDirect || readOutPkt.PathHashCount() != 0 || len(readOutPkt.Path) != 0 || readOutPkt.IsTransport() {
		t.Fatalf("expected 0-hop DIRECT unscoped on Pinto, got route=%s hops=%d transport=%v", readOutPkt.RouteTypeString(), readOutPkt.PathHashCount(), readOutPkt.IsTransport())
	}

	// 2. WRITE to #ireland while near Pinto (0-hop flood from handheld / OwlShack) -> floods into Dublin with #ioi scope!
	wrMsg := &meshcore.GroupTextPayload{
		Timestamp: uint32(now.Unix()) + 11,
		Sender:    "fer",
		Text:      "hello #ireland from pinto!",
	}
	wrEnc, _ := wrMsg.Encrypt(irelandCh.Hash, irelandCh.PSK)
	wrBytes, _ := wrEnc.ToBytes()
	wrPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeGrpTxt, 0),
		PathLength: meshcore.MakePathLen(3, 0), // 0 hops: near hispanas
		Payload:    wrBytes,
	}
	wrRaw, _ := wrPkt.ToBytes()

	wrOutRaw, wrAct, err := eng.RoutePacket(wrRaw, SiteA, now)
	if err != nil {
		t.Fatal(err)
	}
	if wrAct != ActionZeroHopFlood {
		t.Fatalf("expected ActionZeroHopFlood when writing 0-hop near Pinto, got %s", wrAct)
	}
	wrOutPkt, _ := meshcore.PacketFromBytes(wrOutRaw)
	if !ioi.MatchesPacket(wrOutPkt) || wrOutPkt.PathHashCount() != 2 {
		t.Fatalf("expected #ioi scoped flood with 2 bridge hops in Dublin, got route=%s hops=%d", wrOutPkt.RouteTypeString(), wrOutPkt.PathHashCount())
	}

	// Local Pinto repeater echo of that same packet (1 hop) -> dedup-dropped!
	echoPkt := wrPkt.Clone()
	echoPkt.AppendPathHash([]byte{0xa8, 0xba, 0xc6})
	echoRaw, _ := echoPkt.ToBytes()
	if out, eAct, _ := eng.RoutePacket(echoRaw, SiteA, now); out != nil || eAct != ActionDedupDrop {
		t.Fatalf("expected repeater echo to be dedup-dropped, got %s", eAct)
	}

	// 3. WRITE to #madrid while near Dublin using explicit 0-hop DIRECT -> upgrades to unscoped flood in Pinto!
	madMsg := &meshcore.GroupTextPayload{
		Timestamp: uint32(now.Unix()) + 12,
		Sender:    "fer",
		Text:      "hola #madrid desde dublin!",
	}
	madEnc, _ := madMsg.Encrypt(madridCh.Hash, madridCh.PSK)
	madBytes, _ := madEnc.ToBytes()
	madDirect0 := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeDirect, meshcore.PayloadTypeGrpTxt, 0),
		PathLength: meshcore.MakePathLen(3, 0),
		Payload:    madBytes,
	}
	madDirectRaw, _ := madDirect0.ToBytes()

	madOutRaw, madAct, err := eng.RoutePacket(madDirectRaw, SiteB, now)
	if err != nil {
		t.Fatal(err)
	}
	if madAct != ActionZeroHopFlood {
		t.Fatalf("expected 0-hop DIRECT write on #madrid to upgrade to ActionZeroHopFlood, got %s", madAct)
	}
	madOutPkt, _ := meshcore.PacketFromBytes(madOutRaw)
	if madOutPkt.RouteType() != meshcore.RouteTypeFlood || madOutPkt.IsTransport() || madOutPkt.PathHashCount() != 2 {
		t.Fatalf("expected unscoped RouteTypeFlood with 2 bridge hops in Pinto, got route=%s hops=%d", madOutPkt.RouteTypeString(), madOutPkt.PathHashCount())
	}
}

func TestDirectionalZeroHopHomeSiteAndLoopGuard(t *testing.T) {
	ultrabirdID := makeIdentityWithPrefix(t, 0x04)
	ultrabirdPK := ultrabirdID.PublicKey()

	cfg := newTestConfig(t, hex.EncodeToString(ultrabirdPK[:]))
	cfg.AllowedCompanions = []CompanionEntry{
		{PubKey: hex.EncodeToString(ultrabirdPK[:]), Name: "⚡🦅ultrabird"},
		{PubKey: "04", Name: "🟩🦅greenbird"},
	}
	cfg.ZeroHopChannels = []ChannelConfig{
		{Name: "#ireland", HomeSite: "dublin"},
		{Name: "#dublin", HomeSite: "dublin"},
		{Name: "#madrid", HomeSite: "pinto"},
	}

	eng, err := NewBridgeEngine(cfg, nil)
	if err != nil {
		t.Fatal(err)
	}

	now := time.Now()
	ioi := meshcore.NewRegion("#ioi")
	madridCh := meshcore.NewChannelFromHashtag("#madrid")
	irelandCh := meshcore.NewChannelFromHashtag("#ireland")

	// 1. ⚡🦅ultrabird in Dublin writes to #madrid via DUB-DUNDRUM-solarbird (1 repeater hop, #ioi scope)
	//    -> because fromSite (dublin) != homeSite (pinto), it MUST flood unscoped into Pinto instead of clamping!
	madWrite := &meshcore.GroupTextPayload{
		Timestamp: uint32(now.Unix()) + 100,
		Sender:    "⚡🦅ultrabird",
		Text:      "hola #madrid via solarbird en dublin!",
	}
	madEnc, err := madWrite.Encrypt(madridCh.Hash, madridCh.PSK)
	if err != nil {
		t.Fatal(err)
	}
	madBytes, _ := madEnc.ToBytes()
	madViaRepeater := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeGrpTxt, 0),
		PathLength: meshcore.MakePathLen(3, 1),
		Path:       []byte{0x24, 0x41, 0xf6}, // DUB-DUNDRUM-solarbird
		Payload:    madBytes,
	}
	madViaRepeater.SetScope(ioi)
	madViaRaw, _ := madViaRepeater.ToBytes()

	outRaw, act, err := eng.RoutePacket(madViaRaw, SiteB, now)
	if err != nil {
		t.Fatal(err)
	}
	if act != ActionZeroHopFlood {
		t.Fatalf("expected multi-hop #madrid write from Dublin to ActionZeroHopFlood, got %s", act)
	}
	outPkt, _ := meshcore.PacketFromBytes(outRaw)
	if outPkt.RouteType() != meshcore.RouteTypeFlood || outPkt.IsTransport() || outPkt.PathHashCount() != 3 {
		t.Fatalf("expected unscoped flood in Pinto with 3 hops (1 repeater + 2 bridge), got route=%s hops=%d", outPkt.RouteTypeString(), outPkt.PathHashCount())
	}

	// 2. Madrid local mesh traffic on #madrid (fromSite == homeSite == pinto) -> clamped to 0-hop DIRECT in Dublin!
	madLocal := &meshcore.GroupTextPayload{
		Timestamp: uint32(now.Unix()) + 101,
		Sender:    "MadMesh_Rad",
		Text:      "buenas noches madrid",
	}
	madLocalEnc, _ := madLocal.Encrypt(madridCh.Hash, madridCh.PSK)
	madLocalBytes, _ := madLocalEnc.ToBytes()
	madLocalPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeGrpTxt, 0),
		PathLength: meshcore.MakePathLen(3, 4),
		Path:       bytes.Repeat([]byte{0xc4, 0xf2, 0x93}, 4),
		Payload:    madLocalBytes,
	}
	madLocalRaw, _ := madLocalPkt.ToBytes()

	clampRaw, clampAct, err := eng.RoutePacket(madLocalRaw, SiteA, now)
	if err != nil {
		t.Fatal(err)
	}
	if clampAct != ActionZeroHopClamped {
		t.Fatalf("expected Pinto #madrid mesh chatter to clamp in Dublin, got %s", clampAct)
	}
	clampPkt, _ := meshcore.PacketFromBytes(clampRaw)
	if !clampPkt.IsRouteDirect() || clampPkt.PathHashCount() != 0 {
		t.Fatalf("expected 0-hop DIRECT on Dublin, got route=%s hops=%d", clampPkt.RouteTypeString(), clampPkt.PathHashCount())
	}

	// 3. Writing to #ireland from Pinto via MAD-PINTO-CENTRO repeater (1 hop) -> floods into Dublin (#ioi)!
	ireWrite := &meshcore.GroupTextPayload{
		Timestamp: uint32(now.Unix()) + 102,
		Sender:    "⚡🦅ultrabird",
		Text:      "hello #ireland from pinto repeater!",
	}
	ireEnc, _ := ireWrite.Encrypt(irelandCh.Hash, irelandCh.PSK)
	ireBytes, _ := ireEnc.ToBytes()
	ireViaRepeater := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeGrpTxt, 0),
		PathLength: meshcore.MakePathLen(3, 1),
		Path:       []byte{0xa8, 0xba, 0xc6}, // MAD-PINTO-CENTRO
		Payload:    ireBytes,
	}
	ireViaRaw, _ := ireViaRepeater.ToBytes()
	ireOutRaw, ireAct, err := eng.RoutePacket(ireViaRaw, SiteA, now)
	if err != nil {
		t.Fatal(err)
	}
	if ireAct != ActionZeroHopFlood {
		t.Fatalf("expected multi-hop #ireland write from Pinto to flood in Dublin, got %s", ireAct)
	}
	ireOutPkt, _ := meshcore.PacketFromBytes(ireOutRaw)
	if !ioi.MatchesPacket(ireOutPkt) || ireOutPkt.PathHashCount() != 3 {
		t.Fatalf("expected #ioi flood in Dublin with 3 hops, got route=%s hops=%d", ireOutPkt.RouteTypeString(), ireOutPkt.PathHashCount())
	}

	// 4. Cross-bridge ping-pong loop guard:
	//    Simulate dub#8733 -> pin#15168 -> 9 Madrid repeaters -> pin#15171 returning AFTER DedupCache wraparound
	//    (or with a mutated payload byte). Path still contains [dublinBridge, pintoBridge] -> MUST drop!
	dmPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeTxtMsg, 0),
		PathLength: meshcore.MakePathLen(3, 0),
		Payload:    []byte{0xa4, ultrabirdPK[0], 0xde, 0xad, 0xbe, 0xef},
	}
	dmRaw, _ := dmPkt.ToBytes()
	bridgedDMRaw, dmAct, err := eng.RoutePacket(dmRaw, SiteB, now)
	if err != nil || dmAct != ActionIdentityBridged {
		t.Fatalf("expected DM to bridge Dublin->Pinto, got act=%s err=%v", dmAct, err)
	}

	// Evict DedupCache completely (> MaxPacketHashes = 160 entries).
	for i := range 200 {
		filler := &meshcore.Packet{
			Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeTxtMsg, 0),
			PathLength: meshcore.MakePathLen(3, 0),
			Payload:    []byte{byte(i), ultrabirdPK[0], byte(i >> 8), 0xaa, 0xbb},
		}
		fillerRaw, _ := filler.ToBytes()
		_, _, _ = eng.RoutePacket(fillerRaw, SiteB, now)
	}

	echoAfterWrap, _ := meshcore.PacketFromBytes(bridgedDMRaw)
	echoAfterWrap.AppendPathHash([]byte{0x42, 0x38, 0x03})
	echoAfterWrap.AppendPathHash([]byte{0xc4, 0xf2, 0x93})
	echoWrapRaw, _ := echoAfterWrap.ToBytes()

	loopOut, loopAct, err := eng.RoutePacket(echoWrapRaw, SiteA, now.Add(20*time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if loopOut != nil || loopAct != ActionDedupDrop {
		t.Fatalf("expected cross-bridge mesh echo after DedupCache eviction to be DedupDrop, got %s", loopAct)
	}
}

func TestShortPrefixNamedCompanionAllowlist(t *testing.T) {
	// Generate two distinct identities whose Ed25519 public key starts with 0x04:
	// one for 🟩🦅greenbird and one for an unrelated repeater ("EA4HGI QTH").
	makePrefix04 := func() meshcore.LocalIdentity {
		for range 8192 {
			id, err := meshcore.GenerateLocalIdentity(rand.Reader)
			if err != nil {
				t.Fatal(err)
			}
			if id.PublicKey()[0] == 0x04 {
				return id
			}
		}
		t.Fatal("failed to generate 0x04 identity")
		return meshcore.LocalIdentity{}
	}

	greenbirdID := makePrefix04()
	foreignRepeater04 := makePrefix04()
	for greenbirdID.PublicKey() == foreignRepeater04.PublicKey() {
		foreignRepeater04 = makePrefix04()
	}
	impostor04 := makePrefix04()
	for impostor04.PublicKey() == greenbirdID.PublicKey() {
		impostor04 = makePrefix04()
	}

	cfg := newTestConfig(t, "")
	cfg.AllowedCompanions = []CompanionEntry{
		{PubKey: "04", Name: "🟩🦅greenbird"},
	}
	eng, err := NewBridgeEngine(cfg, nil)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()

	// 1. Foreign repeater starting with 0x04 ("EA4HGI QTH") sends ADVERT -> strictly dropped!
	repAdv, err := meshcore.NewAdvert(foreignRepeater04, meshcore.AdvertAppData{
		Type: "REPEATER",
		Name: "EA4HGI QTH",
	}, uint32(now.Unix()))
	if err != nil {
		t.Fatal(err)
	}
	repBytes, _ := repAdv.ToBytes()
	repPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeAdvert, 0),
		PathLength: meshcore.MakePathLen(3, 1),
		Path:       []byte{0x2e, 0xc4, 0xa8},
		Payload:    repBytes,
	}
	repRaw, _ := repPkt.ToBytes()
	if out, act, _ := eng.RoutePacket(repRaw, SiteA, now); out != nil || act != ActionFilteredDrop {
		t.Fatalf("expected 0x04 foreign repeater ADVERT to be filtered_drop, got %s", act)
	}

	// 2. DM involving 0x04 bridges immediately even before ADVERT is seen.
	dmPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeTxtMsg, 0),
		PathLength: meshcore.MakePathLen(3, 0),
		Payload:    []byte{0x99, 0x04, 1, 2, 3, 4},
	}
	dmRaw, _ := dmPkt.ToBytes()
	if out, act, _ := eng.RoutePacket(dmRaw, SiteB, now); out == nil || act != ActionIdentityBridged {
		t.Fatalf("expected 0x04 greenbird DM to bridge, got %s", act)
	}

	// 3. Genuine signed ADVERT from 🟩🦅greenbird bridges AND pins its full 32-byte key!
	gbAdv, err := meshcore.NewAdvert(greenbirdID, meshcore.AdvertAppData{
		Type: "CHAT",
		Name: "🟩🦅greenbird",
	}, uint32(now.Unix())+1)
	if err != nil {
		t.Fatal(err)
	}
	gbBytes, _ := gbAdv.ToBytes()
	gbPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeAdvert, 0),
		PathLength: meshcore.MakePathLen(3, 0),
		Payload:    gbBytes,
	}
	gbRaw, _ := gbPkt.ToBytes()
	if out, act, _ := eng.RoutePacket(gbRaw, SiteB, now); out == nil || act != ActionIdentityBridged {
		t.Fatalf("expected genuine 🟩🦅greenbird ADVERT to bridge, got %s", act)
	}

	// 4. Different 0x04 key spoofing "🟩🦅greenbird" after key pinning -> rejected!
	impAdv, err := meshcore.NewAdvert(impostor04, meshcore.AdvertAppData{
		Type: "CHAT",
		Name: "🟩🦅greenbird",
	}, uint32(now.Unix())+2)
	if err != nil {
		t.Fatal(err)
	}
	impBytes, _ := impAdv.ToBytes()
	impPkt := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeFlood, meshcore.PayloadTypeAdvert, 0),
		PathLength: meshcore.MakePathLen(3, 0),
		Payload:    impBytes,
	}
	impRaw, _ := impPkt.ToBytes()
	if out, act, _ := eng.RoutePacket(impRaw, SiteA, now); out != nil || act != ActionFilteredDrop {
		t.Fatalf("expected spoofed 0x04 ADVERT after key pinning to be filtered_drop, got %s", act)
	}
}

func TestDirectWormholeReturnRouting(t *testing.T) {
	allowedID := makeIdentityWithPrefix(t)
	peerID := makeIdentityWithPrefix(t, allowedID.PublicKey()[0])
	otherID := makeIdentityWithPrefix(t, allowedID.PublicKey()[0], peerID.PublicKey()[0])
	allowedPK := allowedID.PublicKey()

	cfg := newTestConfig(t, hex.EncodeToString(allowedPK[:]))
	eng, err := NewBridgeEngine(cfg, nil)
	if err != nil {
		t.Fatal(err)
	}

	pintoBridge := eng.SiteBridgePubKey(SiteA)
	dublinBridge := eng.SiteBridgePubKey(SiteB)

	// 1. Peer in Dublin replies via ROUTE_TYPE_DIRECT (3-byte hashes) along reverse path:
	// [dublinBridge[:3], pintoBridge[:3], 0x77, 0x88, 0x99] targeting allowedPK[0].
	var pathBytes []byte
	pathBytes = append(pathBytes, dublinBridge[:3]...)
	pathBytes = append(pathBytes, pintoBridge[:3]...)
	pathBytes = append(pathBytes, 0x77, 0x88, 0x99)

	dmPayload := []byte{allowedPK[0], peerID.PublicKey()[0], 0x11, 0x22, 0x33, 0x44, 0x55}
	directIn := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeDirect, meshcore.PayloadTypeTxtMsg, 0),
		PathLength: meshcore.MakePathLen(3, 3),
		Path:       pathBytes,
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
	if pktOut.RouteType() != meshcore.RouteTypeDirect || pktOut.PathHashCount() != 1 || !bytes.Equal(pktOut.Path, []byte{0x77, 0x88, 0x99}) {
		t.Fatalf("expected remaining 3-byte hop [778899], got hops=%d path=%x", pktOut.PathHashCount(), pktOut.Path)
	}

	// 2. Direct ACK routed back through [pintoBridge[:3], dublinBridge[:3]] (even outside flood ackWindow) succeeds.
	var ackPath []byte
	ackPath = append(ackPath, pintoBridge[:3]...)
	ackPath = append(ackPath, dublinBridge[:3]...)
	directAck := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeDirect, meshcore.PayloadTypeAck, 0),
		PathLength: meshcore.MakePathLen(3, 2),
		Path:       ackPath,
		Payload:    []byte{0x01, 0x02, 0x03, 0x04},
	}
	ackRaw, _ := directAck.ToBytes()
	ackOut, ackAct, err := eng.RoutePacket(ackRaw, SiteA, time.Now().Add(10*time.Minute))
	if err != nil || ackOut == nil || ackAct != ActionDirectWormhole {
		t.Fatalf("expected direct ACK through wormhole to succeed, got act=%s err=%v", ackAct, err)
	}

	// 3. Unauthorized direct TXT_MSG between two non-allowlisted nodes is dropped even if addressing the wormhole.
	unauthIn := &meshcore.Packet{
		Header:     meshcore.MakeHeader(meshcore.RouteTypeDirect, meshcore.PayloadTypeTxtMsg, 0),
		PathLength: meshcore.MakePathLen(3, 2),
		Path:       ackPath,
		Payload:    []byte{peerID.PublicKey()[0], otherID.PublicKey()[0], 1, 2, 3, 4},
	}
	unauthRaw, _ := unauthIn.ToBytes()
	if out, uAct, _ := eng.RoutePacket(unauthRaw, SiteA, time.Now()); out != nil || uAct != ActionFilteredDrop {
		t.Fatalf("expected unauthorized direct wormhole packet to be dropped, got %s", uAct)
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

func TestBridgeTunnelRepeaterAdvertsAndPersistence(t *testing.T) {
	stateDir := t.TempDir()

	// Seed a legacy pubkey-only bridge_identities.json (no private seeds) to ensure seamless upgrade.
	legacyJSON := `{"siteAPubHex":"10a7cb0000000000000000000000000000000000000000000000000000000001","siteBPubHex":"483c8c0000000000000000000000000000000000000000000000000000000002"}`
	if err := os.WriteFile(filepath.Join(stateDir, "bridge_identities.json"), []byte(legacyJSON), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg := newTestConfig(t, "")
	cfg.StateDir = stateDir
	cfg.SiteA.AdvertName = " MAD-DUB-TUNNEL" // leading space trimmed cleanly
	cfg.SiteA.PathHashSize = 3
	cfg.SiteA.DirectAdvertMins = 120
	cfg.SiteA.FloodAdvertMins = 720
	cfg.SiteB.AdvertName = "DUB-MAD-TUNNEL"
	cfg.SiteB.PathHashSize = 3
	cfg.SiteB.DirectAdvertMins = 120
	cfg.SiteB.FloodAdvertMins = 720

	eng, err := NewBridgeEngine(cfg, nil)
	if err != nil {
		t.Fatal(err)
	}

	pubA := eng.SiteBridgePubKey(SiteA)
	pubB := eng.SiteBridgePubKey(SiteB)
	if pubA[0] == 0x10 && pubA[1] == 0xa7 && pubA[2] == 0xcb {
		t.Fatalf("expected legacy pubkey-only identity to upgrade to a full signing identity")
	}

	now := time.Now()
	ioi := meshcore.NewRegion("#ioi")

	// 1. First boot -> 12h FLOOD advert is due on both Pinto (unscoped) and Dublin (#ioi).
	rawMadFlood, isFloodMad, err := eng.CheckDueSiteAdvert(SiteA, false, now)
	if err != nil || !isFloodMad || len(rawMadFlood) == 0 {
		t.Fatalf("expected initial Pinto FLOOD advert, got flood=%v len=%d err=%v", isFloodMad, len(rawMadFlood), err)
	}
	pktMad, err := meshcore.PacketFromBytes(rawMadFlood)
	if err != nil {
		t.Fatal(err)
	}
	if pktMad.RouteType() != meshcore.RouteTypeFlood || pktMad.IsTransport() || pktMad.PathHashSize() != 3 || pktMad.PathHashCount() != 0 {
		t.Fatalf("unexpected Pinto FLOOD advert header: route=%s sz=%d hops=%d", pktMad.RouteTypeString(), pktMad.PathHashSize(), pktMad.PathHashCount())
	}
	advMad, err := meshcore.AdvertFromBytes(pktMad.Payload)
	if err != nil || !advMad.Verify() {
		t.Fatalf("expected valid signed Pinto ADVERT, err=%v", err)
	}
	if !bytes.Equal(advMad.PublicKey.PublicKeyBytes(), pubA[:]) || advMad.AppData().Type != "REPEATER" || advMad.AppData().Name != "MAD-DUB-TUNNEL" {
		t.Fatalf("unexpected Pinto ADVERT payload: type=%s name=%q", advMad.AppData().Type, advMad.AppData().Name)
	}
	eng.MarkSiteAdvertSent(SiteA, true, now)

	rawDubFlood, isFloodDub, err := eng.CheckDueSiteAdvert(SiteB, false, now)
	if err != nil || !isFloodDub || len(rawDubFlood) == 0 {
		t.Fatalf("expected initial Dublin FLOOD advert, got flood=%v len=%d err=%v", isFloodDub, len(rawDubFlood), err)
	}
	pktDub, err := meshcore.PacketFromBytes(rawDubFlood)
	if err != nil {
		t.Fatal(err)
	}
	if pktDub.RouteType() != meshcore.RouteTypeTransportFlood || !ioi.MatchesPacket(pktDub) || pktDub.PathHashSize() != 3 || pktDub.PathHashCount() != 0 {
		t.Fatalf("expected Dublin #ioi 3-byte FLOOD advert, got route=%s sz=%d hops=%d", pktDub.RouteTypeString(), pktDub.PathHashSize(), pktDub.PathHashCount())
	}
	advDub, err := meshcore.AdvertFromBytes(pktDub.Payload)
	if err != nil || !advDub.Verify() {
		t.Fatalf("expected valid signed Dublin ADVERT, err=%v", err)
	}
	if !bytes.Equal(advDub.PublicKey.PublicKeyBytes(), pubB[:]) || advDub.AppData().Type != "REPEATER" || advDub.AppData().Name != "DUB-MAD-TUNNEL" {
		t.Fatalf("unexpected Dublin ADVERT payload: type=%s name=%q", advDub.AppData().Type, advDub.AppData().Name)
	}
	eng.MarkSiteAdvertSent(SiteB, true, now)

	// 2. Restarting 10 minutes later preserves exact signing identities AND sends only a 0-hop DIRECT advert (no flood spam!).
	eng2, err := NewBridgeEngine(cfg, nil)
	if err != nil {
		t.Fatal(err)
	}
	if eng2.SiteBridgePubKey(SiteA) != pubA || eng2.SiteBridgePubKey(SiteB) != pubB {
		t.Fatalf("expected signing identities to persist identically across restarts")
	}

	restartRaw, restartFlood, err := eng2.CheckDueSiteAdvert(SiteB, false, now.Add(10*time.Minute))
	if err != nil || restartFlood || len(restartRaw) == 0 {
		t.Fatalf("expected 0-hop DIRECT startup advert on restart within 12h window, got flood=%v len=%d err=%v", restartFlood, len(restartRaw), err)
	}
	restartPkt, _ := meshcore.PacketFromBytes(restartRaw)
	if !restartPkt.IsRouteDirect() || restartPkt.PathHashCount() != 0 {
		t.Fatalf("expected 0-hop DIRECT advert on restart, got route=%s hops=%d", restartPkt.RouteTypeString(), restartPkt.PathHashCount())
	}
	eng2.MarkSiteAdvertSent(SiteB, false, now.Add(10*time.Minute))

	// 3. 30 minutes later (within 2h direct & 12h flood windows, sentStartup=true) -> nothing due.
	if idleRaw, _, err := eng2.CheckDueSiteAdvert(SiteB, true, now.Add(40*time.Minute)); err != nil || idleRaw != nil {
		t.Fatalf("expected no advert due within 2h window, got len=%d err=%v", len(idleRaw), err)
	}

	// 4. 2h15m later -> 0-hop DIRECT advert due; 12h05m later -> scoped FLOOD advert due again.
	if dirRaw, dirFlood, err := eng2.CheckDueSiteAdvert(SiteB, true, now.Add(135*time.Minute)); err != nil || dirFlood || dirRaw == nil {
		t.Fatalf("expected 2h 0-hop DIRECT advert due, got flood=%v nil=%v err=%v", dirFlood, dirRaw == nil, err)
	}
	if flRaw, flFlood, err := eng2.CheckDueSiteAdvert(SiteB, true, now.Add(725*time.Minute)); err != nil || !flFlood || flRaw == nil {
		t.Fatalf("expected 12h FLOOD advert due, got flood=%v nil=%v err=%v", flFlood, flRaw == nil, err)
	}
}
