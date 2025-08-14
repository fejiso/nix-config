{ config, pkgs, ... }:

{
  home.file.".nethackrc".text = ''
    # Most of this is copied from Maud

    OPTIONS=windowtype:tty,toptenwin,hilite_pet,!number_pad
    OPTIONS=fixinv,safe_pet,sortpack,tombstone,color
    OPTIONS=verbose,news,fruit:peyote,autoquiver
    OPTIONS=lit_corridor,menustyle:full,msghistory:100
    OPTIONS=dogname:Catbane,paranoid_hit
    OPTIONS=catname:Ratbane,time
    OPTIONS=horsename:Carrotbane
    OPTIONS=pickup_burden:Unencumbered,pushweapon,scores:2a o
    OPTIONS=!cmdassist,mail,boulder:0,autodig,showexp,showrace,showscore,DECgraphics


    OPTIONS=msg_window:reversed


    OPTIONS=suppress_alert:3.4.3
    OPTIONS=autopickup,pickup_types:%"=/?!+*$

    # Ammo
    #AUTOPICKUP_EXCEPTION="<* dagger*"
    #AUTOPICKUP_EXCEPTION="<* dart*"
    AUTOPICKUP_EXCEPTION="<* arrow*"
    #AUTOPICKUP_EXCEPTION="<* ya*"
    #AUTOPICKUP_EXCEPTION="<* crossbow bolt*"
    #AUTOPICKUP_EXCEPTION="<* throwing star*"
    #AUTOPICKUP_EXCEPTION="<* shuriken*"
    AUTOPICKUP_EXCEPTION="<* named ammo*"

    # Tools
    AUTOPICKUP_EXCEPTION="<* lamp"
    AUTOPICKUP_EXCEPTION="<* lamp called magic"
    AUTOPICKUP_EXCEPTION=">* lamp called oil"
    AUTOPICKUP_EXCEPTION="<* magic whistle"
    AUTOPICKUP_EXCEPTION="<* whistle called magic"
    AUTOPICKUP_EXCEPTION="<* candle*"
    AUTOPICKUP_EXCEPTION="<* marker*"
    AUTOPICKUP_EXCEPTION="<* can of greas*"
    AUTOPICKUP_EXCEPTION="<* camera"
    AUTOPICKUP_EXCEPTION="<* stethoscope"
    AUTOPICKUP_EXCEPTION="<* horn"
    # Before the bad guys use them
    AUTOPICKUP_EXCEPTION="<* create monster"

    # Gems and stones
    AUTOPICKUP_EXCEPTION=">* worthles*"
    AUTOPICKUP_EXCEPTION=">* named glass"
    # This should avoid picking up unknown or unwanted gray types,
    # but still allow "agate stone" et al.
    AUTOPICKUP_EXCEPTION=">* gray stone*"
    AUTOPICKUP_EXCEPTION=">* loadstone*"
    AUTOPICKUP_EXCEPTION=">* rock*"
    AUTOPICKUP_EXCEPTION=">* flint stone*"
    AUTOPICKUP_EXCEPTION=">* touchstone*"
    AUTOPICKUP_EXCEPTION=">* stone called loa*"
    AUTOPICKUP_EXCEPTION=">* stones called loa*"
    # blind or #named
    AUTOPICKUP_EXCEPTION=">? stone*"
    AUTOPICKUP_EXCEPTION=">?? stone*"
    AUTOPICKUP_EXCEPTION=">??? stone*"
    AUTOPICKUP_EXCEPTION=">*ed stone*"

    # Other crap
    AUTOPICKUP_EXCEPTION=">* named out"
    AUTOPICKUP_EXCEPTION=">* named toast"
    AUTOPICKUP_EXCEPTION=">* scare monster*"
    AUTOPICKUP_EXCEPTION=">* corpse*"
    AUTOPICKUP_EXCEPTION=">* huge chunk of meat"
    AUTOPICKUP_EXCEPTION=">* mail*"
    AUTOPICKUP_EXCEPTION=">* junk"
    AUTOPICKUP_EXCEPTION=">* imitation*"
    AUTOPICKUP_EXCEPTION="<* Amulet of Yendor named*"


    # The following are options not in vanilla NetHack:
    #
    #OPTIONS=use_darkgray
    #
    #OPTIONS=showborn
    #
    #OPTIONS=hp_monitor
    #
    OPTIONS=menucolors
    #-------------#
    # Menu Colors #
    #-------------#

    # Color scheme:

    # red = cursed
    # orange = cursed water/paper, -enchant, or bad/dangerous stuff
    # cyan = blessed
    # lightcyan = holy water/paper, +enchant, or "special purpose" stuff
    # white = uncursed water/paper

    # green = useful, always carry
    # lightgreen = emergency/very useful, always have one in open inventory
    # magenta = special goodies, probably leave in stash
    # lightmagenta = very special goodies (magic marker, wishes, poly)
    # yellow = danger (trice corpse, BoH aspode) or Unique Items
    # brown = worthless crap
    # lightblue = un-ID'd crap
    # blue is too dim to read

    # Blessed, cursed, enchanted
    MENUCOLOR=" blessed"=cyan
    MENUCOLOR=" \+[1-9]"=lightcyan
    MENUCOLOR=" \-[1-9]"=orange
    MENUCOLOR=" cursed"=red

    # Un-ID'd
    MENUCOLOR=" (amulet|ring$|potion|scroll|spellbook|wand|gem|tin$|tins$|bag)"=lightblue
    MENUCOLOR=" (amulet|ring|potion|scroll|spellbook|wand|gem|tin|bag)s? (of|called|versus)"=none
    MENUCOLOR=" cursed.* (tin|bag)"=red
    MENUCOLOR=" small bag"=none
    MENUCOLOR=" called .+ or "=lightblue
    MENUCOLOR=" called .*\?"=lightblue
    MENUCOLOR=" gray stone"=lightblue&underline
    MENUCOLOR=" (piece of cloth|opera cloak|ornamental cope|tattered cape|conical hat)"=lightblue
    MENUCOLOR=" (plumed|etched|crested|visored) helmet"=lightblue
    #MENUCOLOR=" (old|padded|riding|fencing) gloves"=lightblue
    MENUCOLOR=" (mud|buckled|riding|snow|hiking|combat|jungle) boots"=lightblue
    MENUCOLOR=" (piece of cloth|opera cloak|ornamental cope|tattered cape|conical hat)"=lightblue

    # Armor
    MENUCOLOR=" dragon scale"=lightmagenta
    MENUCOLOR=" (gloves|gauntlets|yugake)"=lightgreen
    MENUCOLOR=" cursed.* (gloves|gauntlets|yugake)"=lightgreen&underline
    MENUCOLOR=" (levitation boots|boots called lev)"=green
    MENUCOLOR=" helm.* opposite"=lightcyan
    MENUCOLOR=" (gauntlets|gloves|boots) .* fumbl"=orange
    MENUCOLOR=" fumble boots"=orange
    MENUCOLOR=" dunce cap"=orange&underline

    # Tools
    MENUCOLOR=" (magic lamp|lamp called magic)"=magenta
    MENUCOLOR=" blessed (magic lamp|lamp called magic)"=lightmagenta
    MENUCOLOR=" magic marker"=lightmagenta
    MENUCOLOR=" (blessed|cursed) magic marker"=lightmagenta&underline
    MENUCOLOR=" magic marker.* \(1:[0-3]\)"=brown

    MENUCOLOR=" unicorn horn[^[]*$"=lightgreen   # doesn't color skill
    MENUCOLOR=" cursed.* unicorn horn"=lightgreen&underline
    MENUCOLOR=" (blindfold|towel)"=lightgreen
    MENUCOLOR=" cursed.* (blindfold|towel)"=lightgreen&underline
    MENUCOLOR=" stethoscope"=lightgreen
    MENUCOLOR=" cursed.* stethoscope"=lightgreen&underline

    MENUCOLOR=" pick-axe[^[]*$"=green
    MENUCOLOR=" cursed.* pick-axe"=green&underline
    MENUCOLOR=" (key|lock pick|osaku)"=green
    MENUCOLOR=" can of grease"=green
    MENUCOLOR=" cursed.* can of grease"=green&underline

    MENUCOLOR=" (oilskin|sack)"=lightcyan"
    MENUCOLOR=" tinning kit"=lightcyan
    MENUCOLOR=" cursed.* tinning kit"=lightcyan&underline
    MENUCOLOR=" (magic whistle|whistle called magic)"=lightcyan
    MENUCOLOR=" tin whistle"=brown
    MENUCOLOR=" called tin"=brown
    MENUCOLOR=" tin opener"=brown

    # Foodstuffs
    MENUCOLOR=" lumps? of royal jelly"=lightmagenta
    MENUCOLOR=" tins? of (spinach|.*giant meat)"=lightmagenta
    MENUCOLOR=" lizard corpse"=lightgreen
    MENUCOLOR=" (food |K-|C-|cram )ration"=green
    MENUCOLOR=" (gunyoki|lembas wafer)"=green
    MENUCOLOR=" tripe ration"=lightcyan

    #MENUCOLOR=" fortune cookie"=yellow
    MENUCOLOR=" c(hi|o)ckatrice corpse"=yellow
    MENUCOLOR=" tins? of c(hi|o)ckatrice"=yellow
    MENUCOLOR=" cockatrice egg"=yellow

    MENUCOLOR=" (slime mold|candied|cookie)"=green

    # Amulets
    MENUCOLOR=" amulet .* life saving"=lightgreen
    MENUCOLOR=" cursed amulet .* life saving"=lightgreen&underline
    MENUCOLOR=" amulet .* reflect"=lightgreen
    MENUCOLOR=" amulet .* ESP"=lightcyan
    MENUCOLOR=" amulet .* (strang|sleep|change)"=orange

    # Rings
    MENUCOLOR=" ring .* free action"=lightgreen
    MENUCOLOR=" ring .* slow digest"=green
    MENUCOLOR=" ring .* conflict"=green
    MENUCOLOR=" ring .* levitation"=green
    MENUCOLOR=" ring .* teleport control"=green
    MENUCOLOR=" ring .* regeneration"=green
    MENUCOLOR=" ring .* polymorph"=lightcyan
    MENUCOLOR=" ring .* polymorph control"=lightcyan

    # Wands
    MENUCOLOR=" wand (of|called) (wish|death|poly)"=lightmagenta
    MENUCOLOR=" wand (of|called) (teleport|digging)"=lightgreen
    MENUCOLOR=" wand (of|called) (fire|cold|lightning|sleep)"=green
    MENUCOLOR=" wand (of|called) (secret door|create monster|enlighten)"=lightcyan
    MENUCOLOR=" wand (of|called) nothing"=brown

    # Scrolls
    MENUCOLOR=" scrolls? .* genocide"=lightmagenta
    MENUCOLOR=" cursed scrolls? .* genocide"=lightmagenta&underline
    MENUCOLOR=" scrolls? .* enchant (armor|weapon)"=magenta
    MENUCOLOR=" cursed scrolls? .* enchant (armor|weapon)"=magenta&underline
    MENUCOLOR=" scrolls? .* teleport"=lightgreen
    MENUCOLOR=" cursed scrolls? .* teleport"=lightgreen&underline
    MENUCOLOR=" scrolls? .* remove curse"=green
    MENUCOLOR=" cursed scrolls? .* remove curse"=green&underline

    MENUCOLOR="scrolls? .* scare monster"=lightcyan
    MENUCOLOR="scrolls? .* magic mapping"=lightcyan
    MENUCOLOR="scrolls? .* gold detection"=lightcyan
    MENUCOLOR="scrolls? .* taming"=lightcyan
    MENUCOLOR="scrolls? .* charging"=lightcyan

    MENUCOLOR=" unlabeled scroll"=white
    MENUCOLOR=" plain spellbook"=white
    MENUCOLOR=" blank paper"=white
    MENUCOLOR=" blessed unlabeled scroll"=lightcyan
    MENUCOLOR=" blessed plain spellbook"=lightcyan
    MENUCOLOR=" blessed .* blank paper"=lightcyan
    MENUCOLOR=" cursed unlabeled scroll"=orange
    MENUCOLOR=" cursed plain spellbook"=orange
    MENUCOLOR=" cursed .* blank paper"=orange

    # Potions
    MENUCOLOR=" potions? .* (gain ability|enlightenment)"=magenta
    MENUCOLOR=" potions? .* healing"=green
    MENUCOLOR=" potions? .* full healing"=lightgreen
    MENUCOLOR=" potions? .* gain (level|energy)"=lightcyan
    MENUCOLOR=" potions? .* speed"=lightcyan
    MENUCOLOR=" (smoky potion|potions? .* smoky)"=magenta
    MENUCOLOR=" blessed (smoky potion|potions? .* smoky)"=lightmagenta
    #MENUCOLOR=" potions? .* (conf|hallu|blind)"=brown
    MENUCOLOR=" potions? .* acid"=brown

    MENUCOLOR=" clear potion"=white
    MENUCOLOR=" potions? .* water"=white
    MENUCOLOR=" blessed clear potion"=lightcyan
    MENUCOLOR=" blessed potions? .* water"=lightcyan
    MENUCOLOR=" holy water"=lightcyan
    MENUCOLOR=" cursed clear potion"=orange
    MENUCOLOR=" cursed potions? .* water"=orange
    MENUCOLOR=" unholy water"=orange

    # Rocks 'n stuff
    MENUCOLOR=" (luckstone|stones? .* luck|Heart of Ahriman)"=lightgreen
    MENUCOLOR=" cursed (luckstone|stones? .* luck|Heart of Ahriman)"=lightgreen&underline
    MENUCOLOR=" (touchstone|stones? .* touch)"=lightcyan
    MENUCOLOR=" flint stone"=lightcyan
    MENUCOLOR=" rocks?( \(.*\))?$"=brown
    MENUCOLOR=" worthless"=brown
    MENUCOLOR=" (loadstone|stones? called load)"=orange

    # Artifacts R Us
    MENUCOLOR=" (Orb of Detection|Sceptre of Might|Magic Mirror of Merlin)"=lightgreen
    MENUCOLOR=" (Magicbane|Eyes of the Overworld)"=lightgreen
    MENUCOLOR=" (Orb of Fate|Aethiopica|Yendorian Express)"=lightgreen
    MENUCOLOR=" (Master Key of Thievery|Longbow of Diana)"=lightgreen

    MENUCOLOR=" (Bell of Opening|silver bell|[Cc]andelabrum|Book of the Dead|papyrus spellbook)"=yellow
    MENUCOLOR=" Amulet of Yendor"=orange
    MENUCOLOR=" Amulet of Yendor named"=yellow&underline

    # Unstashables
    MENUCOLOR=" bag .* holding"=yellow
    MENUCOLOR=" cursed bag .* holding"=yellow&underline
    MENUCOLOR=" (sack|bag).* named cancel"=yellow
    MENUCOLOR=" bag .* tricks( \([0-9]+:[1-9][0-9]*\))?$"=yellow
    MENUCOLOR=" wand .*(cancel|vanish)"=yellow
    # Looting
    MENUCOLOR="is empty. Do what\?"=none
    MENUCOLOR="Put something into .*"=none
    MENUCOLOR="Take something out of .*"=none

    # Spellcasting
    MENUCOLOR=" 0%"=white
    MENUCOLOR=" [1-9]%"=yellow
    MENUCOLOR=" [12][0-9]%"=yellow
    MENUCOLOR=" [3-5][0-9]%"=brown
    MENUCOLOR=" [6-8][0-9]%"=orange
    MENUCOLOR=" 9[0-9]%"=red
    MENUCOLOR=" 100%"=red
    MENUCOLOR="[a-zA-Z] - [a-zA-Z ]+ [0-9]\*   [a-z]+ +[0-9]+%"=green

    # Enhance
    MENUCOLOR=" \[Basic|Skilled|Master\]$"=green
    MENUCOLOR=" \[Expert|Grand Master\]$"=lightgreen
    MENUCOLOR=" martial arts +\[Expert\]$"=green
    MENUCOLOR="^ *[a-z] - +[a-z -]+ +\[(Unskilled|Basic|Skilled|Expert|Master)\]$"=lightmagenta

    # Force colors
    MENUCOLOR="\\{R\\}"=red
    MENUCOLOR="\\{B\\}"=blue
    MENUCOLOR="\\{C\\}"=cyan
    MENUCOLOR="\\{G\\}"=green
    MENUCOLOR="\\{Y\\}"=yellow
    MENUCOLOR="\\{[MP]\\}"=magenta
    MENUCOLOR="\\{O\\}"=orange
    MENUCOLOR="\\{W\\}"=white
    MENUCOLOR="\\{L\\}"=black
    MENUCOLOR="\\{y\\}"=gray
    MENUCOLOR="\\{g\\}"=lightgreen
    MENUCOLOR="\\{b\\}"=lightblue
    MENUCOLOR="\\{[mp]\\}"=lightmagenta
    MENUCOLOR="\\{c\\}"=lightcyan
    MENUCOLOR="\\{N\\}"=none
    MENUCOLOR="\\{X\\}"=bold
    MENUCOLOR="\\{x\\}"=dim
    MENUCOLOR="\\{U\\}"=underline
    MENUCOLOR="\\{I\\}"=inverse
    MENUCOLOR="\\{K\\}"=blink



    #
    #OPTIONS=paranoid_hit,paranoid_quit,paranoid_remove
    #
    #OPTIONS=sortloot:full
    #
    OPTIONS=showbuc
    #
    #OPTIONS=win_edge
    #
    #OPTIONS=show_obj_sym

    # For more information on what you can set in your nethackrc file, refer to:
    #    http://www.nethack.org/v343/Guidebook.html#_TOCentry_42
    # or http://nethack.wikia.com/wiki/Options
    # Happy hacking!
  '';
}