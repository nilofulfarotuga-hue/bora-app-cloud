
$r = Invoke-RestMethod 'https://tienda.mercadona.es/api/categories/112/' -Headers @{'User-Agent'='Mozilla/5.0'}
Write-Host "Top-level keys:"
$r.PSObject.Properties.Name | ForEach-Object { Write-Host "  $_" }
Write-Host "name: $($r.name)"

$cats = $r.categories
if ($cats -and $cats.Count -gt 0) {
    Write-Host "Has .categories: $($cats.Count)"
    $sub = $cats[0]
    Write-Host "Subcat name: $($sub.name)"
    $prods = $sub.products
    if ($prods -and $prods.Count -gt 0) {
        Write-Host "Products count: $($prods.Count)"
        $p = $prods[0]
        Write-Host "Product fields:"
        $p.PSObject.Properties.Name | ForEach-Object { $k=$_; Write-Host "  $k = $($p.$k)" }
    } else {
        Write-Host "No products in sub.products"
        Write-Host "Subcat fields:"
        $sub.PSObject.Properties.Name | ForEach-Object { Write-Host "  $_" }
    }
} else {
    Write-Host "No .categories field"
    # Try direct products
    $prods = $r.products
    if ($prods) {
        Write-Host "Has .products: $($prods.Count)"
    }
}
