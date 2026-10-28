-- 27/10/2026 (Claude.ai). Versão de TESTE (nome temporário) para comparar com a atual antes de trocar.
-- Achado da missão Boom! Burger: categoria mista "Bebidas e cervejas" marcava Água e Coca-Cola como +18.
CREATE OR REPLACE FUNCTION public.produto_e_maior_18_v2_teste(p_name text, p_category text, p_tax text, p_root text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  with v as (
    select lower(coalesce(p_name,'')) n,
           lower(coalesce(p_category,'')) c,
           coalesce(p_tax,'') t,
           lower(coalesce(p_root,'')) r
  ), f as (
    select n, c, t, r,
      -- palavras que só existem em bebida alcoólica
      n ~ '(\mvinhos?\M|\mcervejas?\M|\mcervezas?\M|\mbeer\M|whisk(e)?y\M|vodka|\mgin\M|\mginebra\M|\mrum\M|(?<!-)\mron\M(?!-)|\mlicor(es)?\M|aguardente|aguardiente|baga[cç]o|brandy|conhaque|cognac|tequila|champanhe|champagne|espumante|sangria|\msidras?\M|\mcidra\M|moscatel|verm(u|o)uth|vermute|\mmartini\M|absinto|cacha[cç]a|prosecco|lambrusco|medronho|\mginjas?\M|ginjinha|amarguinha|pachar[aá]n|\mpisco\M|\maperol\M|campari|\mpastis\M|\mricard\M|baileys|beir[aã]o|j[aä]germeister|vinho do porto|\mtawny\M|\mlbv\M|\mporto\M.*(\mruby\M|\d+ ?anos|vintage|reserva|colheita|branco|tinto|ros[eé]))' as forte_nome,
      (t = 'Vinhos & Espirituosas'
         or r ~ '^(.lcool|vinhos e espumantes|bebidas espirituosas|cervejas e sidras)$'
         or c ~ '(\mvinhos?\M|cervej|espirituos|whisk(e)?y|\mgin\M|vodka|\mrum\M|licor|aguardente|champanhe|espumante|sangria|\msidras?\M|cocktails?\M|garrafeira exclusiva|^.lcool)') as forte_cat,
      -- categoria MISTA: junta refrigerantes/águas/sumos com cerveja/vinho/sidra no mesmo nome
      (c ~ '^bebidas\s*(e|,|&|/|-)\s*(cervej|vinho|sidra)'
         or c ~ '(cervej\w*|vinhos?|sidras?)\s*(e|,|&|/|-)\s*(bebidas|refrigerantes?|sumos?|[aá]guas?)'
         or (c ~ '(refrigerantes?|\msumos?\M|\m[aá]guas?\M)' and c ~ '(cervej|\mvinhos?\M|\msidras?\M)')) as cat_mista
    from v
  )
  select case
    -- 1. Tabaco e nicotina (não os ambientadores "anti-tabaco" nem as gomas para deixar de fumar)
    when n ~ '(\mtabaco|\mcigarr(o|os|ilha|ilhas)\M|\mcharutos?\M|\miqos\M|\mheets\M|\mterea\M|\mvapes?\M|nicotina|cigarro eletr)'
         and n !~ '(ambientador|\mvelas?\M|anti[- ]?tabaco|\maroma|\mgomas?\M|pastilh|adesivo|nicotinell|\mspray\M|chocolate|brinquedo|guloseima)'
      then true
    -- 2. Explicitamente sem álcool
    when n ~ '(sem [aá]lcool|sem alcohol|sin alcohol|alcohol[ -]?free|non[ -]?alcoholic|(^|[^0-9,.])0[,.]0(?![0-9])|(^|[^0-9,.])0 ?%|(?<!cola )\mzero\M|bock free)'
      then false
    -- 3. Não é bebida, diga o nome o que disser
    when n ~ '(vinagre|\mmolhos?\M|tempero|especiaria|levedura|whiskas|c[aá]psulas?|saca[- ]?rolhas|abridor|decanta|ambientador|\mvelas?\M|sabonete|\mbanho\M|barbear|champ[oô]\M|perfume|col[oó]nia|desodori|iluminador|batom|verniz|\mlego\M|brinquedo|\mra[cç][aã]o\M|frutos secos|desidrat|^caixa|ginger (ale|beer)|cervejeir|\mbomb(om|ons|ons)\M|ballotin|\mgelados?\M|\mbolos?\M|bolacha|biscoit|\mpudim|presunto|chouri|salsich|bacalhau|compota|frigor[ií]fico|\mbaldes?\M|salva[- ]?gotas)'
      then false
    when c ~ '(acess[oó]rios|copos e|/mesa/|casa e jardim|casa, bricolage|bricolage|pintura|drogaria|animais|brinquedos|papelaria|ilumina|roupa|ferramentas|decora|beleza|higiene|cabelo|frutos secos|limpeza|velas|molhos|tempero|medicamentos)'
      then false
    -- 4. O nome diz bebida alcoólica
    when forte_nome then true
    -- 4b. Categoria mista ("Bebidas e cervejas"): água, refrigerante ou sumo sem palavra nem marca de álcool no nome NÃO é +18 (27/10/2026)
    when cat_mista
         and n ~ '(\m[aá]guas?\M|coca[- ]?cola|\mpepsi\M|\msprite\M|\mfanta\M|\m7 ?up\M|ice ?tea|nestea|lipton|compal|\msumol\M|\msumos?\M|refrigerante|t[oó]nica|schweppes|red ?bull|\mmonster\M|guaran[aá]|limonada|frisumo|\mluso\M|vitalis|salutis|caramulo|penacova|monchique|\mfastio\M|vimeiro|kombucha|laranjada|gasosa)'
         and n !~ '[aá]gua[\s-]+p[eé]\M'
         and n !~ '(\msagres\M|super ?bock|heineken|\mcorona\M|desperados|somersby|carlsberg|guinness|budweiser|stella artois|\mmahou\M|estrella damm|\mcoral\M|bohemia|leffe|hoegaarden|erdinger|\mtagus\M|smirnoff|\mabsolut\M|bacardi|jameson|johnnie walker|jack daniel|famous grouse|chivas|ballantine|\mgordon|bombay|beefeater|tanqueray|eristoff|malibu|macieira|casal garcia|\mmateus\M|bandida|\mletra\M)'
         and not public.texto_pede_maior_18(n)
      then false
    -- 5. A categoria diz bebida alcoólica (excepto petiscos e copos mal arrumados na secção)
    when forte_cat and n !~ '(\mcaju\M|am[eê]ndoa|amendoim|pinh[aã]o|gengibre|\mmanga\M|\mbanana\M|(?<!com )\mcopos?\M|(?<!com )c[aá]lice|\mflutes?\M|(?<!com )ch[aá]venas?)'
      then true
    -- 6. Marcas de bebida alcoólica, só com contexto de bebida (volume, garrafa, lata, pack)
    when n ~ '(\msagres\M|super ?bock|heineken|\mcorona\M|desperados|somersby|carlsberg|guinness|budweiser|stella artois|\mmahou\M|estrella damm|\mcoral\M|bohemia|leffe|hoegaarden|erdinger|\mtagus\M|smirnoff|\mabsolut\M|bacardi|jameson|johnnie walker|jack daniel|famous grouse|chivas|ballantine|\mgordon|bombay|beefeater|tanqueray|eristoff|malibu|macieira|casal garcia|\mmateus\M)'
         and n ~ '(\d+ ?(cl|ml|l|lt|litros?)\M|garrafa|\mlatas?\M|\mpack\M|\mbarril|\mmini\M|long ?neck|\mcaneca|imperial|\mcopo)'
      then true
    else false
  end
  from f;
$function$;
