
# Inserir produtos Mercadona diretamente via Supabase REST API
# Evita ler SQL no contexto — usa REST API com service_role key

$SupabaseUrl = "https://ojykpzwqrtusfeakzrna.supabase.co"
$ServiceKey  = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MzAwMDcyOCwiZXhwIjoyMDg4NTc2NzI4fQ.TFbiYG1SQEB5gNpUb1721mvkL5JU7hJaSsrru4KkE8A"
$RestaurantId = "mercadona-guarda"
$BatchSize = 100

$Headers = @{
    "Authorization" = "Bearer $ServiceKey"
    "apikey"        = $ServiceKey
    "Content-Type"  = "application/json"
    "Prefer"        = "return=minimal"
}

function Get-CatPT($catES) {
    if ($catES -match "Aceite|Arroz|Legumbre|Pasta|conserva|Tomate|Salsa|Azucar|Harina|vinagre|Sopa|Caldo") { return "Mercearia" }
    if ($catES -match "Agua|refresco|Cerveza|Vino|cafe|zumo|infusion|Ron|Cava|Whisky|Licor|Sidra") { return "Bebidas" }
    if ($catES -match "Aperitivo|Patatas|Frutos secos|snack|Aceituna") { return "Snacks" }
    if ($catES -match "Chocolate|Caramelo|Dulce|Cacao") { return "Chocolates e Doces" }
    if ($catES -match "Bebe|Infantil|Nino") { return "Bebé" }
    if ($catES -match "Carne|Pollo|Ternera|Cerdo|Cordero|Pavo") { return "Carne" }
    if ($catES -match "Pescado|Marisco|Salmon|Atun|Merluza|Bacalao") { return "Peixe" }
    if ($catES -match "Congelado") { return "Congelados" }
    if ($catES -match "Detergente|Limpieza|Suavizante|Fregasuelos|Bayeta|Estropajo") { return "Limpeza" }
    if ($catES -match "Fruta|Fresas|Platano|Naranja|Manzana") { return "Frutas" }
    if ($catES -match "Verdura|Hortaliza|Lechuga|Tomate|Cebolla|Zanahoria") { return "Legumes" }
    if ($catES -match "Higiene|Jabon|Desodorante|Papel higienico|Celulosa|Gel|Champu") { return "Higiene" }
    if ($catES -match "Lacteo|Leche|Yogur|Mantequilla|Margarina|Nata|Kefir") { return "Laticínios" }
    if ($catES -match "Queso|Embutido|Charcuteria|Jamon|Salchich|Chorizo") { return "Charcutaria" }
    if ($catES -match "Mascota|Gato|Perro|Acuario") { return "Animais" }
    if ($catES -match "Pan|Bolleria|Galleta|Bizcocho|Croissant") { return "Padaria" }
    if ($catES -match "Menaje|Hogar|Cocina|Casa|Basura|Bolsa") { return "Casa" }
    if ($catES -match "Fitnes|Proteina|Vitamina|Suplemento") { return "Fitness e Proteínas" }
    return "Mercearia"
}

$SubCatIds = @(112,115,116,117,156,163,158,159,161,162,135,133,132,118,121,120,89,95,92,97,90,216,219,218,217,164,166,181,174,168,170,173,171,169,86,81,83,84,88,46,38,47,37,42,43,44,40,45,78,80,79,48,52,49,51,50,58,54,56,53,147,148,154,155,150,149,151,884,152,145,122,123,127,130,129,126,201,199,203,202,192,189,185,191,188,187,186,190,194,196,198,213,214,27,28,29,77,72,75,226,237,241,234,235,233,231,230,232,229,243,238,239,244,206,207,208,210,212,32,34,31,36,222,221,225,65,66,69,59,60,62,64,68,71,897,138,140,142,105,110,111,106,103,109,108,104,107,99,100,143,98)

# 1. Obter nomes existentes na Mercadona para evitar duplicados
Write-Host "A obter produtos existentes na Mercadona..."
$existingNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$page = 0
do {
    $offset = $page * 1000
    $url = "$SupabaseUrl/rest/v1/products?restaurant_id=eq.$RestaurantId&select=name&limit=1000&offset=$offset"
    $existing = Invoke-RestMethod $url -Headers $Headers
    foreach ($p in $existing) { [void]$existingNames.Add($p.name) }
    $page++
} while ($existing.Count -eq 1000)
Write-Host "Existentes: $($existingNames.Count) produtos"

# 2. Fetch da API Mercadona e filtrar novos
Write-Host "A buscar produtos da API Mercadona..."
$newProducts = [System.Collections.Generic.List[object]]::new()

foreach ($catId in $SubCatIds) {
    if ($newProducts.Count -ge 2000) { break }
    try {
        $resp = Invoke-RestMethod "https://tienda.mercadona.es/api/categories/$catId/" `
            -Headers @{'User-Agent'='Mozilla/5.0'; 'Accept'='application/json'} -TimeoutSec 15

        foreach ($subcat in $resp.categories) {
            $catPT = Get-CatPT $subcat.name
            foreach ($p in $subcat.products) {
                $rawName = $p.display_name
                if (-not $rawName) { continue }
                # Limpar nome: remover chars problemáticos
                $cleanName = $rawName -replace "[^\u0020-\u007E\u00C0-\u00FF]", ""
                if ($existingNames.Contains($cleanName)) { continue }

                $price = 0.0
                if ($p.price_instructions -and $p.price_instructions.bulk_price) {
                    $price = [double]($p.price_instructions.bulk_price -replace ',','.')
                }

                $newProducts.Add([PSCustomObject]@{
                    id            = [guid]::NewGuid().ToString()
                    restaurant_id = $RestaurantId
                    name          = $cleanName
                    description   = ($subcat.name -replace "[^\u0020-\u007E\u00C0-\u00FF]", "")
                    photo_url     = if ($p.thumbnail) { $p.thumbnail } else { "" }
                    price         = $price
                    category      = $catPT
                    unit          = if ($p.packaging) { $p.packaging } else { "" }
                    is_available  = $true
                    is_popular    = $false
                    is_on_sale    = $false
                })
            }
        }
        Start-Sleep -Milliseconds 150
    } catch {}
}

Write-Host "Novos produtos a inserir: $($newProducts.Count)"

# 3. Inserir em batches de 100
$inserted = 0
$errors   = 0
$arr = $newProducts.ToArray()

for ($i = 0; $i -lt $arr.Count; $i += $BatchSize) {
    $end   = [Math]::Min($i + $BatchSize, $arr.Count) - 1
    $batch = @($arr[$i..$end])

    # Converter para JSON compacto com encoding UTF-8 explícito
    $body    = $batch | ConvertTo-Json -Depth 2 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

    try {
        $resp = Invoke-WebRequest "$SupabaseUrl/rest/v1/products" `
            -Method POST `
            -Headers $Headers `
            -Body $bodyBytes `
            -ContentType "application/json; charset=utf-8"

        $inserted += $batch.Count
        Write-Host "OK: $inserted / $($arr.Count) inseridos"
    } catch {
        $errors++
        $errBody = $_.ErrorDetails.Message
        Write-Host "ERRO batch $([Math]::Floor($i/$BatchSize)+1): $errBody" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== RESULTADO ==="
Write-Host "Inseridos com sucesso: $inserted"
Write-Host "Erros: $errors"
