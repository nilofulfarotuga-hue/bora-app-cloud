
# Gera SQL em formato bulk INSERT (batches de 200 VALUES)
# Muito mais eficiente que 2025 INSERTs individuais

$RestaurantId = "mercadona-guarda"
$OutputDir = "C:\Users\danil\Desktop\projetosflutter\bora_app\scripts"
$BatchSize = 200

$SubCatIds = @(112,115,116,117,156,163,158,159,161,162,135,133,132,118,121,120,89,95,92,97,90,216,219,218,217,164,166,181,174,168,170,173,171,169,86,81,83,84,88,46,38,47,37,42,43,44,40,45,78,80,79,48,52,49,51,50,58,54,56,53,147,148,154,155,150,149,151,884,152,145,122,123,127,130,129,126,201,199,203,202,192,189,185,191,188,187,186,190,194,196,198,213,214,27,28,29,77,72,75,226,237,241,234,235,233,231,230,232,229,243,238,239,244,206,207,208,210,212,32,34,31,36,222,221,225,65,66,69,59,60,62,64,68,71,897,138,140,142,105,110,111,106,103,109,108,104,107,99,100,143,98)

function Get-CatPT($catES) {
    if ($catES -match "Aceite|Arroz|Legumbre|Pasta|conserva|Tomate|Salsa|Azucar|Harina|vinagre") { return "Mercearia" }
    if ($catES -match "Agua|refresco|Cerveza|Vino|cafe|zumo|infusion|Ron|Cava|Whisky") { return "Bebidas" }
    if ($catES -match "Aperitivo|Patatas|Frutos secos|snack") { return "Snacks" }
    if ($catES -match "Chocolate|Caramelo|Dulce|Cacao") { return "Chocolates e Doces" }
    if ($catES -match "Bebe|Infantil|Nino") { return "Bebé" }
    if ($catES -match "Carne|Pollo|Ternera|Cerdo") { return "Carne" }
    if ($catES -match "Pescado|Marisco|Salmon|Atun") { return "Peixe" }
    if ($catES -match "Congelado") { return "Congelados" }
    if ($catES -match "Detergente|Limpieza|Suavizante|Fregasuelos") { return "Limpeza" }
    if ($catES -match "Fruta") { return "Frutas" }
    if ($catES -match "Verdura|Hortaliza") { return "Legumes" }
    if ($catES -match "Higiene|Jabon|Desodorante|Papel higienico|Celulosa") { return "Higiene" }
    if ($catES -match "Lacteo|Leche|Yogur|Mantequilla|Margarina") { return "Laticínios" }
    if ($catES -match "Queso|Embutido|Charcuteria|Jamon") { return "Charcutaria" }
    if ($catES -match "Mascota|Gato|Perro") { return "Animais" }
    if ($catES -match "Pan|Bolleria|Galleta") { return "Padaria" }
    if ($catES -match "Menaje|Hogar|Cocina|Casa") { return "Casa" }
    return "Mercearia"
}

function Escape-Sql($s) {
    if ($null -eq $s) { return "" }
    # Remove caracteres nao-ASCII problemáticos, mantém apenas ASCII + chars PT
    $clean = $s.ToString() -replace "[^\u0020-\u00FF]", ""
    return $clean.Replace("'", "''")
}

# Colectar todos os produtos
$allProducts = [System.Collections.Generic.List[hashtable]]::new()

foreach ($catId in $SubCatIds) {
    if ($allProducts.Count -ge 2100) { break }
    try {
        $url = "https://tienda.mercadona.es/api/categories/$catId/"
        $resp = Invoke-RestMethod $url -Headers @{'User-Agent'='Mozilla/5.0'; 'Accept'='application/json'} -TimeoutSec 15

        foreach ($subcat in $resp.categories) {
            $catPT = Get-CatPT $subcat.name
            foreach ($p in $subcat.products) {
                if (-not $p.display_name) { continue }
                $price = 0.0
                if ($p.price_instructions -and $p.price_instructions.bulk_price) {
                    $price = [double]($p.price_instructions.bulk_price -replace ',','.')
                }
                $allProducts.Add(@{
                    name    = Escape-Sql $p.display_name
                    desc    = Escape-Sql $subcat.name
                    photo   = Escape-Sql $p.thumbnail
                    price   = $price
                    cat     = Escape-Sql $catPT
                    unit    = Escape-Sql $p.packaging
                })
            }
        }
        Start-Sleep -Milliseconds 150
    } catch {}
}

Write-Host "Total produtos coletados: $($allProducts.Count)"

# Dividir em batches e gerar SQL
$batchNum = 0
$i = 0
while ($i -lt $allProducts.Count) {
    $batchNum++
    $batch = $allProducts | Select-Object -Skip $i -First $BatchSize
    $i += $BatchSize

    $values = @()
    foreach ($p in $batch) {
        $values += "('$($p.name)','$($p.desc)','$($p.photo)',$($p.price),'$($p.cat)','$($p.unit)')"
    }
    $valStr = $values -join ",`n"

    $sql = @"
INSERT INTO products (id,restaurant_id,name,description,photo_url,price,category,unit,is_available,is_popular,is_on_sale)
SELECT gen_random_uuid(),'$RestaurantId',v.name,v.desc,v.photo,v.price,v.cat,v.unit,true,false,false
FROM (VALUES
$valStr
) AS v(name,desc,photo,price,cat,unit)
WHERE NOT EXISTS (
  SELECT 1 FROM products
  WHERE restaurant_id='$RestaurantId' AND LOWER(products.name)=LOWER(v.name)
);
"@

    $outFile = "$OutputDir\batch_$batchNum.sql"
    $sql | Out-File -FilePath $outFile -Encoding UTF8
    Write-Host "Batch $batchNum gerado: $($batch.Count) produtos -> $outFile"
}

Write-Host ""
Write-Host "=== TOTAL: $($allProducts.Count) produtos em $batchNum batches ==="
