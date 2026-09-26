-- data/legendary.lua -- which species the wonder trade refuses to hand out as
-- an ordinary tier-4 result.
--
-- national_dex's records carry no legendary flag (its generated species table
-- has no such field -- checked against 0.35.7 directly), and the registry
-- record the engine owns has none either, so a list has to live somewhere.
-- This one is the same roster g9-battle-sample's own encounter gate carries
-- (its LEGENDARY set, itself written out for the identical reason), with the
-- handful of restricted legendaries that set is missing added on: Type: Null
-- and Silvally (both restricted), and the Gen 9 mythical Pecharunt.
--
-- Mythicals are in here deliberately: the request puts "legendaries and
-- mystics" together in the 5-star bracket, and every mythical that matters
-- (Mew, Celebi, Jirachi, Deoxys, Phione, Manaphy, Darkrai, Shaymin, Arceus,
-- Victini, Keldeo, Meloetta, Genesect, Diancie, Hoopa, Volcanion, Magearna,
-- Marshadow, Zeraora, Meltan, Melmetal, Zarude, Pecharunt) is already spelled
-- out.  A FORM of a legendary counts too -- CHARIZARD_MEGA_X is checked
-- through its baseSpecies, the same way the encounter gate checks it, so a
-- Mega of a restricted species cannot slip into tier 4.
return {
  -- Gen 1-2
  ARTICUNO = true, ZAPDOS = true, MOLTRES = true, MEWTWO = true, MEW = true,
  RAIKOU = true, ENTEI = true, SUICUNE = true, LUGIA = true, HO_OH = true,
  CELEBI = true,
  -- Gen 3
  REGIROCK = true, REGICE = true, REGISTEEL = true, LATIAS = true,
  LATIOS = true, KYOGRE = true, GROUDON = true, RAYQUAZA = true,
  JIRACHI = true, DEOXYS = true,
  -- Gen 4
  UXIE = true, MESPRIT = true, AZELF = true, DIALGA = true, PALKIA = true,
  HEATRAN = true, REGIGIGAS = true, GIRATINA = true, CRESSELIA = true,
  PHIONE = true, MANAPHY = true, DARKRAI = true, SHAYMIN = true,
  ARCEUS = true,
  -- Gen 5
  VICTINI = true, COBALION = true, TERRAKION = true, VIRIZION = true,
  TORNADUS = true, THUNDURUS = true, RESHIRAM = true, ZEKROM = true,
  LANDORUS = true, KYUREM = true, KELDEO = true, MELOETTA = true,
  GENESECT = true,
  -- Gen 6
  XERNEAS = true, YVELTAL = true, ZYGARDE = true, DIANCIE = true,
  HOOPA = true, VOLCANION = true,
  -- Gen 7 (the Ultra Beasts are included -- they are encounter-restricted
  -- the same way in every game that ships them)
  TAPU_KOKO = true, TAPU_LELE = true, TAPU_BULU = true, TAPU_FINI = true,
  COSMOG = true, COSMOEM = true, SOLGALEO = true, LUNALA = true,
  NIHILEGO = true, BUZZWOLE = true, PHEROMOSA = true, XURKITREE = true,
  CELESTEELA = true, KARTANA = true, GUZZLORD = true, NECROZMA = true,
  MAGEARNA = true, MARSHADOW = true, POIPOLE = true, NAGANADEL = true,
  STAKATAKA = true, BLACEPHALON = true, ZERAORA = true, MELTAN = true,
  MELMETAL = true, TYPE_NULL = true, SILVALLY = true,
  -- Gen 8
  ZACIAN = true, ZAMAZENTA = true, ETERNATUS = true, KUBFU = true,
  URSHIFU = true, ZARUDE = true, REGIELEKI = true, REGIDRAGO = true,
  GLASTRIER = true, SPECTRIER = true, CALYREX = true, ENAMORUS = true,
  -- Gen 9
  KORAIDON = true, MIRAIDON = true, WO_CHIEN = true, CHIEN_PAO = true,
  TING_LU = true, CHI_YU = true, OKIDOGI = true, MUNKIDORI = true,
  FEZANDIPITI = true, OGERPON = true, TERAPAGOS = true, PECHARUNT = true,
}
