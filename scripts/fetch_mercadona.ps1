
# Fetch Mercadona API -> SQL INSERT para novos produtos
# Estrutura: GET /api/categories/{id}/ -> .categories[].products[]

$RestaurantId = "mercadona-guarda"
$OutputFile = "C:\Users\danil\Desktop\projetosflutter\bora_app\scripts\mercadona_inserts.sql"
$Target = 2000  # candidatos a inserir (mais do que suficiente para +1500 novos)

$SubCatIds = @(112,115,116,117,156,163,158,159,161,162,135,133,132,118,121,120,89,95,92,97,90,216,219,218,217,164,166,181,174,168,170,173,171,169,86,81,83,84,88,46,38,47,37,42,43,44,40,45,78,80,79,48,52,49,51,50,58,54,56,53,147,148,154,155,150,149,151,884,152,145,122,123,127,130,129,126,201,199,203,202,192,189,185,191,188,187,186,190,194,196,198,213,214,27,28,29,77,72,75,226,237,241,234,235,233,231,230,232,229,243,238,239,244,206,207,208,210,212,32,34,31,36,222,221,225,65,66,69,59,60,62,64,68,71,897,138,140,142,105,110,111,106,103,109,108,104,107,99,100,143,98)

function Get-CatPT($catES) {
    $map = @{
        "Aceite"="Mercearia"; "vinagre"="Mercearia"; "sal "="Mercearia"
        "Agua"="Bebidas"; "refresco"="Bebidas"; "Cerveza"="Bebidas"; "Vino"="Bebidas"; "cafe"="Bebidas"; "zumo"="Bebidas"; "infusion"="Bebidas"
        "Aperitivo"="Snacks"; "Patatas"="Snacks"; "Frutos secos"="Snacks"
        "Arroz"="Mercearia"; "Legumbre"="Mercearia"; "Pasta"="Mercearia"; "conserva"="Mercearia"; "Tomate"="Mercearia"; "Salsa"="Mercearia"
        "Azucar"="Mercearia"; "Harina"="Mercearia"
        "Chocolate"="Chocolates e Doces"; "Caramelo"="Chocolates e Doces"; "Dulce"="Chocolates e Doces"
        "Bebe"="Bebé"; "Infantil"="Bebé"; "Nino"="Bebé"
        "Carne"="Carne"; "Pollo"="Carne"; "Ternera"="Carne"; "Cerdo"="Carne"
        "Pescado"="Peixe"; "Marisco"="Peixe"; "Salmon"="Peixe"
        "Congelado"="Congelados"
        "Detergente"="Limpeza"; "Limpieza"="Limpeza"; "Suavizante"="Limpeza"; "Fregasuelos"="Limpeza"
        "Fruta"="Frutas"
        "Verdura"="Legumes"; "Hortaliza"="Legumes"
        "Higiene"="Higiene"; "Jabon"="Higiene"; "Desodorante"="Higiene"; "Papel"="Higiene"; "Celulosa"="Higiene"
        "Lacteo"="Laticínios"; "Leche"="Laticínios"; "Yogur"="Laticínios"; "Mantequilla"="Laticínios"; "Margarina"="Laticínios"
        "Queso"="Charcutaria"; "Embutido"="Charcutaria"; "Charcuteria"="Charcutaria"; "Jamon"="Charcutaria"
        "Mascota"="Animais"; "Gato"="Animais"; "Perro"="Animais"
        "Pan"="Padaria"; "Bolleria"="Padaria"; "Galleta"="Padaria"
        "Menaje"="Casa"; "Hogar"="Casa"; "Cocina"="Casa"
    }
    foreach ($key in $map.Keys) {
        if ($catES -like "*$key*") { return $map[$key] }
    }
    return "Mercearia"
}

function Escape-Sql($s) {
    if ($null -eq $s) { return "" }
    return $s.ToString().Replace("'", "''")
}

$sql_lines = [System.Collections.Generic.List[string]]::new()
$sql_lines.Add("-- Mercadona novos produtos - $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$sql_lines.Add("-- Inserir apenas se nome nao existir ja na Mercadona")

$total = 0

foreach ($catId in $SubCatIds) {
    if ($total -ge $Target) { break }
    try {
        $url = "https://tienda.mercadona.es/api/categories/$catId/"
        $resp = Invoke-RestMethod $url -Headers @{'User-Agent'='Mozilla/5.0'; 'Accept'='application/json'} -TimeoutSec 15

        # Navegar nas subcategorias do resultado
        foreach ($subcat in $resp.categories) {
            $catNameES = $subcat.name
            $catPT = Get-CatPT $catNameES

            foreach ($p in $subcat.products) {
                $name = $p.display_name
                if (-not $name) { continue }

                $price = 0.0
                if ($p.price_instructions -and $p.price_instructions.bulk_price) {
                    $price = [double]($p.price_instructions.bulk_price -replace ',','.')
                }

                $photo = ""
                if ($p.thumbnail) { $photo = $p.thumbnail }

                $unit = ""
                if ($p.packaging) { $unit = $p.packaging }

                $nameEsc  = Escape-Sql $name
                $photoEsc = Escape-Sql $photo
                $unitEsc  = Escape-Sql $unit
                $descEsc  = Escape-Sql $catNameES
                $catEsc   = Escape-Sql $catPT

                $sql = "INSERT INTO products (id,restaurant_id,name,description,photo_url,price,category,unit,is_available,is_popular,is_on_sale) " +
                       "SELECT gen_random_uuid(),'$RestaurantId','$nameEsc','$descEsc','$photoEsc',$price,'$catEsc','$unitEsc',true,false,false " +
                       "WHERE NOT EXISTS (SELECT 1 FROM products WHERE restaurant_id='$RestaurantId' AND LOWER(name)=LOWER('$nameEsc'));"

                $sql_lines.Add($sql)
                $total++
            }
        }
        Start-Sleep -Milliseconds 150
    }
    catch {
        # silenciar erros de rede e continuar
    }
}

$sql_lines | Out-File -FilePath $OutputFile -Encoding UTF8
Write-Host "DONE: $total candidatos | SQL -> $OutputFile"
