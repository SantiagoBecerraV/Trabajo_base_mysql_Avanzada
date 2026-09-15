-- ===========================================
-- CONSULTAS
-- ===========================================

USE ecommerce_db;

-- Generar un ranking con los 10 productos que han generado más ingresos.
SELECT 
	p.nombre AS producto,
	p.id_producto,
	SUM(dv.cantidad) AS unidades_vendidas,
	SUM(dv.cantidad * precio_unitario_congelado) AS total_ingresos
FROM productos p
INNER JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
INNER JOIN ventas v ON dv.id_venta = v.id_venta
WHERE v.estado != 'Cancelado'
GROUP BY p.id_producto, p.nombre
ORDER BY total_ingresos DESC
LIMIT 10;

-- Identificar los productos en el 10% inferior de ventas 

SELECT 
    p.id_producto,
    p.nombre,
    c.nombre AS categoria,
    COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas,
    p.stock,
    p.precio
FROM productos p
LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
LEFT JOIN categorias c ON p.id_categoria = c.id_categoria
GROUP BY p.id_producto, p.nombre, c.nombre, p.stock, p.precio
ORDER BY unidades_vendidas ASC
LIMIT 2;


-- Listar los 5 clientes con el mayor valor de vida

SELECT
	c.id_cliente,
	c.nombre,
	c.apellido,
	COUNT(v.id_venta) AS total_compras,
	SUM(v.total) AS ltv_total
FROM clientes c
INNER JOIN ventas v ON c.id_cliente = v.id_cliente
WHERE estado != 'Cancelado'
GROUP BY c.id_cliente, c.nombre, c.apellido
ORDER BY ltv_total DESC
LIMIT 5;

-- Mostrar las ventas totales agrupadas por mes y año.

SELECT 
    YEAR(v.fecha_venta) AS año,
    MONTH(v.fecha_venta) AS mes,
    DATE_FORMAT(v.fecha_venta, '%Y-%m') AS periodo,
    COUNT(v.id_venta) AS cantidad_ventas,
    SUM(v.total) AS total_ventas
FROM ventas v
GROUP BY YEAR(v.fecha_venta), MONTH(v.fecha_venta), DATE_FORMAT(v.fecha_venta, '%Y-%m')
ORDER BY año ASC, mes ASC;
   
 
-- Calcular el número de nuevos clientes registrados por trimestre.
   
SELECT
    YEAR(fecha_registro) AS anio,
    MONTH(fecha_registro) AS numero_mes,
    QUARTER(fecha_registro) AS trimestre_numero,
    CONCAT('Q', QUARTER(fecha_registro), '-', YEAR(fecha_registro)) AS trimestre_etiqueta,
    COUNT(id_cliente) AS clientes_nuevos
FROM clientes 
GROUP BY 
    YEAR(fecha_registro),
    MONTH(fecha_registro),
    QUARTER(fecha_registro),
    CONCAT('Q', QUARTER(fecha_registro), '-', YEAR(fecha_registro))
ORDER BY 
    anio ASC, 
    trimestre_numero ASC;

-- Determinar qué porcentaje de clientes ha realizado más de una compra.
WITH ComprasPorCliente AS (
    SELECT 
        id_cliente,
        COUNT(id_venta) AS total_compras
    FROM ventas
    WHERE estado != 'Cancelado'
    GROUP BY id_cliente
)
SELECT 
    COUNT(id_cliente) AS total_clientes_compradores,
    COUNT(CASE WHEN total_compras > 1 THEN 1 END) AS clientes_recurrentes,
    ROUND(
        (COUNT(CASE WHEN total_compras > 1 THEN 1 END) * 100.0) / COUNT(id_cliente), 
        2
    ) AS tasa_compra_repetida_porcentaje
FROM ComprasPorCliente;

-- Identificar pares de productos que a menudo se compran en la misma transacción.
SELECT 
    p1.nombre AS producto_1,
    p2.nombre AS producto_2,
    COUNT(*) AS veces_comprados_juntos
FROM detalle_ventas dv1
INNER JOIN detalle_ventas dv2 
    ON dv1.id_venta = dv2.id_venta 
    AND dv1.id_producto < dv2.id_producto
INNER JOIN productos p1 ON dv1.id_producto = p1.id_producto
INNER JOIN productos p2 ON dv2.id_producto = p2.id_producto
INNER JOIN ventas v ON dv1.id_venta = v.id_venta
WHERE v.estado != 'Cancelado'
GROUP BY 
    p1.id_producto, 
    p1.nombre, 
    p2.id_producto, 
    p2.nombre
ORDER BY veces_comprados_juntos DESC;

-- Calcular la tasa de rotación de stock para cada categoría de producto.

SELECT 
    c.id_categoria,
    c.nombre AS categoria,
    COALESCE(SUM(p.stock), 0) AS stock_actual,
    COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas_totales,
    ROUND(
        COALESCE(SUM(dv.cantidad), 0) / NULLIF(SUM(p.stock), 0), 
        2
    ) AS tasa_rotacion_stock
FROM categorias c
LEFT JOIN productos p ON c.id_categoria = p.id_categoria
LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
GROUP BY c.id_categoria, c.nombre
ORDER BY tasa_rotacion_stock DESC;

-- Listar productos cuyo stock actual está por debajo de su umbral mínimo.

-- Un truco de un senior como yo Santiago Becerra Creacion columna
ALTER TABLE productos
ADD COLUMN stock_minimo INT NOT NULL DEFAULT 10;

UPDATE productos
SET stock_minimo = CASE 
    WHEN precio > 2000000 THEN 5      
    WHEN precio > 500000 THEN 15      
    ELSE 20                           
END;

SELECT id_producto, nombre, precio, stock, stock_minimo 
FROM productos;

SELECT 
    p.id_producto,
    p.nombre,
    c.nombre AS categoria,
    pv.nombre AS proveedor,
    p.stock AS stock_actual,
    p.stock_minimo,
    (p.stock_minimo - p.stock) AS unidades_faltantes,
    p.precio
FROM productos p
INNER JOIN categorias c ON p.id_categoria = c.id_categoria
INNER JOIN proveedores pv ON p.id_proveedor = pv.id_proveedor
WHERE p.stock < p.stock_minimo
ORDER BY unidades_faltantes DESC;

-- Identificar clientes que agregaron productos pero no completaron una venta en un período determinado.

SELECT
	c.id_cliente,
	CONCAT(c.nombre, '', c.apellido) AS nombre_cliente,
	c.email,
	v.id_venta,
	v.fecha_venta,
	v.estado,
	v.total AS valor_carrito,
    DATEDIFF(NOW(), v.fecha_venta) AS dias_desde_abandono
FROM ventas v
INNER JOIN clientes c ON v.id_cliente = c.id_cliente
WHERE v.estado IN ('Pendiente de pago', 'Cancelado')
    AND v.fecha_venta >= DATE_SUB(NOW(), INTERVAL 60 DAY)
ORDER BY v.total DESC, v.fecha_venta DESC;