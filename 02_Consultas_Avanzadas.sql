-- ===========================================
-- CONSULTAS
-- ===========================================

USE ecommerce_db;


-- 1. TOP 10 PRODUCTOS MAS VENDIDOS
SELECT
    p.id_producto,
    p.nombre                                             AS producto,
    c.nombre                                             AS categoria,
    SUM(dv.cantidad)                                     AS unidades_vendidas,
    SUM(dv.cantidad * dv.precio_unitario_congelado)      AS ingresos_totales
FROM productos p
INNER JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
INNER JOIN ventas v          ON v.id_venta     = dv.id_venta
INNER JOIN categorias c      ON c.id_categoria = p.id_categoria
WHERE v.estado <> 'Cancelado'
GROUP BY p.id_producto, p.nombre, c.nombre
ORDER BY ingresos_totales DESC
LIMIT 10;


-- 2. PRODUCTOS CON BAJAS VENTAS
WITH ingresos_por_producto AS (
    SELECT
        p.id_producto,
        p.nombre,
        p.activo,
        COALESCE(SUM(dv.cantidad), 0)                                AS unidades_vendidas,
        COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) AS ingresos_totales
    FROM productos p
    LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
    LEFT JOIN ventas v          ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
    GROUP BY p.id_producto, p.nombre, p.activo
),
deciles AS (
    SELECT
        ingresos_por_producto.*,
        NTILE(10) OVER (ORDER BY ingresos_totales ASC) AS decil
    FROM ingresos_por_producto
)
SELECT
    id_producto,
    nombre AS producto,
    unidades_vendidas,
    ingresos_totales,
    decil,
    'Candidato a descontinuar' AS recomendacion
FROM deciles
WHERE decil = 1
ORDER BY ingresos_totales ASC;


-- 3. CLIENTES VIP
SELECT
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    c.email,
    COUNT(v.id_venta)                 AS total_compras,
    SUM(v.total)                      AS ltv_total,
    ROUND(AVG(v.total), 2)            AS ticket_promedio
FROM clientes c
INNER JOIN ventas v ON v.id_cliente = c.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.id_cliente, c.nombre, c.apellido, c.email
ORDER BY ltv_total DESC
LIMIT 5;


-- 4. ANALISIS DE VENTAS MENSUALES
SELECT
    YEAR(v.fecha_venta)                          AS anio,
    MONTH(v.fecha_venta)                         AS numero_mes,
    DATE_FORMAT(v.fecha_venta, '%Y-%m')          AS periodo,
    COUNT(v.id_venta)                            AS cantidad_ventas,
    SUM(v.total)                                 AS total_vendido,
    ROUND(AVG(v.total), 2)                       AS ticket_promedio
FROM ventas v
WHERE v.estado <> 'Cancelado'
GROUP BY YEAR(v.fecha_venta), MONTH(v.fecha_venta), DATE_FORMAT(v.fecha_venta, '%Y-%m')
ORDER BY anio, numero_mes;


-- 5. CRECIMIENTO DE CLIENTES
WITH registros_por_trimestre AS (
    SELECT
        YEAR(c.fecha_registro)    AS anio,
        QUARTER(c.fecha_registro) AS trimestre,
        COUNT(*)                  AS clientes_nuevos
    FROM clientes c
    GROUP BY YEAR(c.fecha_registro), QUARTER(c.fecha_registro)
)
SELECT
    anio,
    trimestre,
    CONCAT('Q', trimestre, '-', anio)            AS etiqueta,
    clientes_nuevos,
    SUM(clientes_nuevos) OVER (
        ORDER BY anio, trimestre
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                            AS acumulado_historico
FROM registros_por_trimestre
ORDER BY anio, trimestre;


-- 6. TASA DE COMPRA REPETIDA
WITH compras_por_cliente AS (
    SELECT
        v.id_cliente,
        COUNT(v.id_venta) AS total_compras
    FROM ventas v
    WHERE v.estado <> 'Cancelado'
    GROUP BY v.id_cliente
)
SELECT
    COUNT(*)                                                       AS clientes_compradores,
    SUM(CASE WHEN total_compras > 1 THEN 1 ELSE 0 END)             AS clientes_recurrentes,
    ROUND(
        SUM(CASE WHEN total_compras > 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
        2
    )                                                              AS tasa_compra_repetida_pct
FROM compras_por_cliente;


-- 7. PRODUCTOS COMPRADOS JUNTOS FRECUENTEMENTE
SELECT
    p1.nombre        AS producto_1,
    p2.nombre        AS producto_2,
    COUNT(*)         AS veces_comprados_juntos
FROM detalle_ventas dv1
INNER JOIN detalle_ventas dv2
        ON dv2.id_venta = dv1.id_venta
       AND dv2.id_producto > dv1.id_producto
INNER JOIN ventas v     ON v.id_venta = dv1.id_venta
INNER JOIN productos p1 ON p1.id_producto = dv1.id_producto
INNER JOIN productos p2 ON p2.id_producto = dv2.id_producto
WHERE v.estado <> 'Cancelado'
GROUP BY p1.id_producto, p1.nombre, p2.id_producto, p2.nombre
ORDER BY veces_comprados_juntos DESC, producto_1;


-- 8. ROTACION DE INVENTARIO
SELECT
    c.id_categoria,
    c.nombre                                                AS categoria,
    COALESCE(inv.stock_total, 0)                            AS stock_actual,
    COALESCE(ven.unidades_vendidas, 0)                      AS unidades_vendidas,
    ROUND(
        COALESCE(ven.unidades_vendidas, 0) / NULLIF(inv.stock_total, 0),
        4
    )                                                       AS tasa_rotacion
FROM categorias c
LEFT JOIN (
    SELECT id_categoria, SUM(stock) AS stock_total
    FROM productos
    GROUP BY id_categoria
) inv ON inv.id_categoria = c.id_categoria
LEFT JOIN (
    SELECT p.id_categoria, SUM(dv.cantidad) AS unidades_vendidas
    FROM detalle_ventas dv
    JOIN ventas v    ON v.id_venta = dv.id_venta
    JOIN productos p ON p.id_producto = dv.id_producto
    WHERE v.estado <> 'Cancelado'
    GROUP BY p.id_categoria
) ven ON ven.id_categoria = c.id_categoria
ORDER BY tasa_rotacion DESC;


-- 9. PRODUCTOS QUE NECESITAN REABASTECIMIENTO
SELECT
    p.id_producto,
    p.nombre                       AS producto,
    c.nombre                       AS categoria,
    pv.nombre                      AS proveedor,
    pv.email_contacto              AS contacto_proveedor,
    p.stock                        AS stock_actual,
    p.stock_minimo,
    (p.stock_minimo - p.stock)     AS unidades_faltantes,
    p.costo                        AS costo_unitario,
    (p.stock_minimo - p.stock) * p.costo AS inversion_requerida
FROM productos p
INNER JOIN proveedores pv ON pv.id_proveedor = p.id_proveedor
LEFT  JOIN categorias  c  ON c.id_categoria  = p.id_categoria
WHERE p.activo = TRUE
  AND p.stock < p.stock_minimo
ORDER BY unidades_faltantes DESC;


-- 10. ANALISIS DE CARRITO ABANDONADO (SIMULADO)
SELECT
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    c.email,
    v.id_venta,
    v.fecha_venta,
    v.estado,
    v.total AS valor_carrito,
    DATEDIFF(NOW(), v.fecha_venta) AS dias_desde_abandono
FROM ventas v
INNER JOIN clientes c ON c.id_cliente = v.id_cliente
WHERE v.estado IN ('Pendiente de Pago', 'Cancelado')
  AND v.fecha_venta >= NOW() - INTERVAL 60 DAY
ORDER BY v.total DESC, v.fecha_venta DESC;