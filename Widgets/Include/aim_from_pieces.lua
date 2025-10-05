-- by Helwor, license GNU GPL, v2 or later
-- old version but more appropriate when looking for the relevant piece of an active unit
-- handmade
-- see aim_from_pieces_2.lua for the automated version made only for simulating range of a model
-- as I can't access scripts from widget, I recopy the aimFrom piece name here
-- this is to work around the mistaking spHaveFreeLineOfFire callin
-- and this workaround is because no callin work properly to check if my unit gonna be able to shoot a particular ground target or not
-- it will give the actual piece from where we have to aim and therefore verify if our unit actually gonna aim
-- however,once the aiming animation is over, we can check for line of fire, but it still not make a 100% certainty it will shoot, some rare case can happen
if WG.aim_from_pieces then
    return WG.aim_from_pieces
end
WG.aim_from_pieces = {
     amphaa               = 'torso'
    ,amphassault          = 'turret'
    ,amphbomb             = 'firepoint'
    ,amphfloater          = 'barrel'
    ,amphimpulse          = 'aimpoint'
    ,amphlaunch           = 'pelvis'
    ,amphraid             = 'head'
    ,amphriot             = 'flaremain'
    ,amphsupport          = 'head'
    --
    ,armcom               = 'torso'
    --
    ,assaultcruiser       = function(num) return (select(num, "flturret", "frturret", "slturret", "srturret", "mlturret", "mrturret")) end
    --
    ,benzcom              = 'torso'
    ,bomberassault        = 'bomb'
    ,bomberdisarm         = 'Drop' -- not used, made special behaviour for this
    ,bomberheavy          = 'drop'
    ,bomberheavy_old      =  nil -- there is actually no AimFrom script function 
    ,bomberprec           = 'drop'
    ,bomberriot           =  nil -- there is actually no AimFrom script function 
    ,bomberstrike         = 'flaremissilel' -- or 'flaremissiler' -- it alternates, we cannot know in advance
    --
    ,chicken              = "head"
    ,chicken_blimpy       = 'dodobomb'
    ,chicken_digger       = "head"
    ,chicken_dragon       = function(num)  return (select(num, 'firepoint','spike1','spike2','spike3','firepoint','body')) end
    ,chicken_leaper       = "head"
    ,chicken_pigeon       = 'head'
    ,chicken_rafflesia    = 'body'
    ,chicken_roc          = function(num) return (select(num, 'firepoint','spore1','spore2','spore3')) or 'body' end
    ,chicken_shield       = 'firepoint'
    ,chicken_spidermonkey = "head"
    ,chicken_sporeshooter = "head"
    ,chicken_tiamat       = function(num) return num==2 and 'spike2' or num==4 and 'body' or 'firepoint' end
    ,chickena             = function(num) return num==1 and 'head' or 'body'end
    ,chickenbroodqueen    = function(num) return num==2 and 'spike1' or num==3 and 'spike2' or num==4 and 'spike3' or 'firepoint' end
    ,chickenflyerqueen    = function(num) return (select(num, 'firepoint','spore1','spore2','spore3')) or 'body' end
    ,chickenlandqueen     = function(num) return (select(num, 'firepoint','firepoint','spore1','spore2','spore3')) or 'body' end
    ,chickena             = function(num) return num==1 and 'head' or 'body' end
    ,chickenc             = 'head'
    ,chickend             = 'firepoint'
    ,chickenf             = 'head'
    ,chickenr             = 'head'
    ,chickens             = 'head'
    ,chickenspire         = 'firepoint'
    ,chickenwurm          = 'fire'
    ,chickenblobber       = 'head'
    --
    ,cloakaa              = "head"
    ,cloakarty            = 'center'
    ,cloakassault         = 'aim'
    ,cloakheavyraid       = 'head'
    ,cloakraid            = 'head'--,'head' -- even though the script tell to aim from 'head' the LoF checking is wrong--after verification, it actually aim from flare which is also the weapon position
    ,cloakriot            = 'chest'
    ,cloakskirm           = 'gunemit'
    ,cloaksnipe           = 'shoulderr'
    --
    ,commrecon            = 'armhold'
    ,commstrike           = function(num) return num == 3 and 'UnderMuzzle' or num == 5 and 'Palm' or 'Shield'end
    ,commsupport          = 'armhold'
    ,corcom_alt           = 'torso'
    ,cremcom              = 'torso'
    --
    ,cruisemissile        = 'base'
    ,dronefighter         = 'DroneMain'
    ,dronecarry           = 'gunpod'
    ,droneheavyslow       = "base"
    ,dronelight           = "base"
    --
    ,dynassault           = function(_,id,weapOrder)
                             local pieceMap = Spring.GetUnitPieceMap(id)
                             local rcannon_flare= pieceMap.rgattlingflare and 'rgattlingflare' or 'rcannon_flare'
                             local lcannon_flare = pieceMap.bonuscannonflare and 'bonuscannonflare' or 'lnanoflare'
                             local isManual = Spring.GetUnitRulesParam(id, "comm_weapon_manual_"..weapOrder)==1
                             return not isManual and 'pelvis' or weapOrder==1 and rcannon_flare or lcannon_flare
                          end
    ,dynknight            = function(_,id,weapOrder)
                             local isManual = Spring.GetUnitRulesParam(id, "comm_weapon_manual_"..weapOrder)==1
                             return not isManual and 'torso' or weapOrder==1 and 'flarel' or 'flarer'
                          end
    ,dynrecon             = 'pelvis'
    ,dynstrike            = function(_,id,weapOrder)
                             local isManual = Spring.GetUnitRulesParam(id, "comm_weapon_manual_"..weapOrder)==1
                             return not isManual and 'Shield' or weapOrder==1 and 'Palm' or 'RightMuzzle'
                          end
    ,dynsupport           = 'head'
    --
    ,grebe                = 'aimpoint'
    --
    ,gunshipaa            = 'base'
    ,gunshipassault       = 'body'
    ,gunshipemp           = 'housing'
    ,gunshipheavyskirm    = 'eye'
    ,gunshipheavytrans    = function(num) return (select(num, 'RTurretBase','LTurretBase','FrontTurret')) end
    ,gunshipkrow          = function(num) return (select(num, 'RightTurretSeat','LeftTurretSeat','subpoint','RearTurretSeat','Base','Base')) end
    ,gunshipraid          = 'gun'
    ,gunshipskirm         = 'base'
    --
    ,hoveraa              = 'turret'
    ,hoverarty            = 'aim'
    ,hoverassault         = 'turret'
    ,hoverdepthcharge     = 'pads'
    ,hoverheavyraid       = 'turret'
    ,hoverminer           = "flare"
    ,hoverraid            = 'turret'
    ,hoverriot            = 'barrel'
    ,hovershotgun         = "turret"
    ,hoverskirm           = 'turret'
    --
    ,jumpaa               = 'torso'
    ,jumparty             = 'torso'
    ,jumpassault          = 'ram'
    ,jumpblackhole        = 'chest'
    ,jumpcon              = 'torso'
    ,jumpraid             = 'low_head'
    ,jumpscout            = 'gun'
    ,jumpskirm            = 'head'
    ,jumpsumo             = function(num) return (select(num, 'b_eye', 'l_turret', 'r_turret', 'l_turret', 'r_turret', 'b_eye')) end
    --
    ,mahlazer             = 'SatelliteMuzzle' -- useless, this is not the piece aiming at ground/units and this is not the correct unit to check for,
    ,starlight_satellite  = 'SatelliteMuzzle' -- not used anymore -- note:was bad technique using 'LimbA1' piece which was one of the few pieces to move (but only 75% reliable) while satellite is aiming
                                                 -- found out an effective way by projecting the satellite's weapon's vectors

    ,nebula               = function(num) return num == 5 and 'base' or 'turret'..num end
    ,planefighter         = 'base'
    ,planeheavyfighter    = 'base'
    ,pw_hq                = 'drone'
    ,pw_wormhole          = 'drone'
    ,pw_wormhole2         = 'drone'
    ,raveparty            = 'spindle'
    --
    ,roost                = "emit"

    ,shieldfelon          = "shot1"
    ,shieldaa             = 'pod'
    ,shieldarty           = 'pelvis'
    ,shieldassault        = 'head'
    ,shieldraid           = 'head'
    ,shieldriot           = 'torso'
    ,shieldscout          = 'pelvis'
    ,shieldskirm          = 'popup'
    --
    ,shipaa               = function(num) return num == 1 and 'fturret' or 'bturret' end
    ,shiparty             = 'turret'
    ,shipassault          = function(num) return num == 1 and 'turret' or 'missile1' end
    ,shipcarrier          = 'Radar'
    ,shipscout            = 'missile'
    ,shipheavyarty        = function(num)return (select(num, 'turret1', 'turret2', 'turret3')) end
    ,shipriot             = function(num) return num == 1 and 'gunb' or 'gunf' end
    ,shipskirm            = 'turret'
    ,shiptorpraider       = "Turret"
    ,staticantinuke       = "aimpoint"
    --
    ,spideraa             = 'turret'
    ,spideranarchid       = 'aim'
    ,spiderantiheavy      = 'turret'
    ,spiderassault        = 'turret'
    ,spidercrabe          = function() return num==1 and 'turret' or 'rocket' end
    ,spideremp            = 'turret'
    ,spiderriot           = 'barrel'
    ,spiderscout          = 'turret'
    ,spiderskirm          = 'box'
    --
    --
    ,staticarty           = 'sleeve'
    ,staticheavyarty      = 'query'
    --
    ,striderarty          = 'launchers'
    ,striderbantha        = function(num) return  num==2 and 'torso' or 'headflare' end
    ,striderdante         = 'torso'
    ,striderdozer         = function(num) return (select(num, 'base', 'turret1', 'turret2')) end
    ,striderdetriment     = function(num) return (select(num, 'larmcannon', 'rarmcannon', 'AAturret', 'headlaser2', 'shouldercannon', 'lfoot', 'lfoot', 'lfoot')) end
    ,striderscorpion      = function(num) return (select(num, 'body','tailgun','tailgun','gunl','gunr')) end
    ,striderantiheavy     = 'head'
    --
    ,subraider            = 'firepoint'
    ,subtacmissile        = 'aimpoint'
    --
    ,tankaa               = "aim"
    ,tankarty             = 'barrel'
    ,tankassault          = 'turret'
    ,tankcon              = 'turret'
    ,tankheavyarty        = 'triple'
    ,tankheavyassault     = function(num) return num==1 and 'turret1' or 'turret2' end
    ,tankheavyraid        = 'turret'
    ,tankraid             = 'turret'
    ,tankriot             = 'sleeve'
    --
    ,turretaaclose        = 'turret'
    ,turretaafar          = 'mc_rocket_ho'
    ,turretaaflak         = 'trueaim'
    ,turretaaheavy        = 'turret'
    ,turretaalaser        = "aim"
    ,turretantiheavy      = "barrel"
    ,turretgauss          = "AimProxy"
    ,turretlaser          = 'barrel'
    ,turretmissile        = 'pod'
    ,turretriot           = 'turret'
    --
    ,turretemp            = 'aim'
    ,turretheavy          = function(num) return num==1 and 'cannonAim' or 'heatrayBase' end
    ,turretheavylaser     = 'holder'
    ,turretimpulse        = 'center'
    ,turretsunlance       = 'breech'
    ,turrettorp           = 'base'
    --
    ,vehassault           = 'turret'
    ,vehaa                = 'firepoint'
    ,vehcapture           = 'flare'
    ,vehraid              = 'turret'
    ,vehriot              = 'turret'
    ,vehscout             = 'turret'
    ,vehsupport           = 'aim'
    ,veharty              = 'swivel'
    --
    ,wolverine_mine       = 'bomblet1' -- but it varies depends on animation from bomblet1 to bomblet5
    ,zenith               = 'firept'
}

return WG.aim_from_pieces