DROP DATABASE IF EXISTS ecommerce_db;
CREATE DATABASE ecommerce_db;
USE ecommerce_db;


-- ====================================
-- TABLAS

-- tabla de categorias
CREATE TABLE categorias (
    id_categoria INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    descripcion TEXT
);

-- tabla de proveedores
CREATE TABLE proveedores (
    id_proveedor INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    email_contacto VARCHAR(150) UNIQUE,
    telefono_contacto VARCHAR(30)
);

-- tabla de productos
CREATE TABLE productos (
    id_producto INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL UNIQUE,
    descripcion TEXT,
    precio DECIMAL(12,2) NOT NULL,
    costo DECIMAL(12,2) NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    sku VARCHAR(40) NOT NULL UNIQUE,
    fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    activo BOOLEAN DEFAULT TRUE,
    id_categoria INT NOT NULL,
    id_proveedor INT NOT NULL,
    FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria),
    FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor),
    CHECK (precio > 0),
    CHECK (costo >= 0),
    CHECK (stock >= 0)
);

-- tabla de clientes
CREATE TABLE clientes (
    id_cliente INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL,
    apellido VARCHAR(80) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    contrasena VARCHAR(255) NOT NULL,
    direccion_envio VARCHAR(255),
    fecha_registro DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- tabla de ventas (el encabezado del pedido)
CREATE TABLE ventas (
    id_venta INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    fecha_venta DATETIME DEFAULT CURRENT_TIMESTAMP,
    estado ENUM('Pendiente de Pago', 'Procesando', 'Enviado', 'Entregado', 'Cancelado') DEFAULT 'Pendiente de Pago',
    total DECIMAL(14,2) DEFAULT 0,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente),
    CHECK (total >= 0)
);

-- tabla detalle_ventas
-- esta es la tabla que conecta ventas con productos (muchos a muchos)
-- ojo: no usamos productos.precio directo porque ese precio puede cambiar despues
CREATE TABLE detalle_ventas (
    id_detalle INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT NOT NULL,
    id_producto INT NOT NULL,
    cantidad INT NOT NULL,
    precio_unitario_congelado DECIMAL(12,2) NOT NULL,
    FOREIGN KEY (id_venta) REFERENCES ventas(id_venta),
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto),
    CHECK (cantidad > 0)
);


-- ====================================
-- DATOS DE PRUEBA

-- categorias
INSERT INTO categorias (id_categoria, nombre, descripcion) VALUES
(1, 'Electronica', 'Dispositivos electronicos y accesorios'),
(2, 'Ropa', 'Prendas de vestir'),
(3, 'Hogar', 'Articulos para la casa'),
(4, 'Deportes', 'Implementos deportivos'),
(5, 'Libros', 'Libros y revistas');

-- proveedores
INSERT INTO proveedores (id_proveedor, nombre, email_contacto, telefono_contacto) VALUES
(1, 'TecnoAndina SAS', 'ventas@tecnoandina.com', '6076543210'),
(2, 'Importadora Digital', 'contacto@impdigital.com', '6012345678'),
(3, 'Textiles del Oriente', 'compras@textilesoriente.co', '6076781234'),
(4, 'Casa y Cocina SA', 'proveedor@casaycocina.com', '6044448899'),
(5, 'Deportes Total', 'info@deportestotal.com', '6023216547');

-- productos

INSERT INTO productos (id_producto, nombre, descripcion, precio, costo, stock, sku, fecha_creacion, activo, id_categoria, id_proveedor) VALUES
(1, 'Laptop Vortex 14', 'Portatil 14 pulgadas 16GB RAM SSD 512GB', 3200000, 2400000, 25, 'ELE-LAP-001', '2025-09-01 08:00:00', TRUE, 1, 1),
(2, 'Mouse Inalambrico Nova', 'Mouse optico inalambrico 2.4GHz', 85000, 48000, 120, 'ELE-MOU-002', '2025-09-01 08:05:00', TRUE, 1, 1),
(3, 'Teclado Mecanico K80', 'Teclado mecanico switch azul', 320000, 195000, 40, 'ELE-TEC-003', '2025-09-03 09:30:00', TRUE, 1, 2),
(4, 'Audifonos Bluetooth Pulse', 'Audifonos con cancelacion de ruido', 240000, 130000, 8, 'ELE-AUD-004', '2025-09-05 10:15:00', TRUE, 1, 2),
(5, 'Camiseta Algodon Basica', 'Camiseta 100% algodon varios colores', 55000, 22000, 200, 'ROP-CAM-005', '2025-09-10 11:00:00', TRUE, 2, 3),
(6, 'Jean Slim Fit', 'Pantalon jean corte slim', 145000, 70000, 60, 'ROP-JEA-006', '2025-09-10 11:10:00', TRUE, 2, 3),
(7, 'Cafetera Express Milano', 'Cafetera express 15 bares', 480000, 300000, 18, 'HOG-CAF-007', '2025-09-15 14:20:00', TRUE, 3, 4),
(8, 'Juego de Sabanas King', 'Sabanas 400 hilos tamano king', 190000, 95000, 5, 'HOG-SAB-008', '2025-09-15 14:35:00', TRUE, 3, 4),
(9, 'Balon de Futbol Pro', 'Balon profesional numero 5', 110000, 55000, 75, 'DEP-BAL-009', '2025-09-20 16:00:00', TRUE, 4, 5),
(10, 'Mancuernas 10kg Par', 'Par de mancuernas con caucho', 260000, 160000, 30, 'DEP-MAN-010', '2025-09-20 16:10:00', TRUE, 4, 5),
(11, 'Novela El Ultimo Viaje', 'Novela de 320 paginas', 45000, 20000, 50, 'LIB-NOV-011', '2025-10-01 09:00:00', TRUE, 5, 5);

-- clientes
INSERT INTO clientes (id_cliente, nombre, apellido, email, contrasena, direccion_envio, fecha_registro) VALUES
(1, 'Andres', 'Cardenas', 'andres.cardenas@correo.com', '$2y$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'Cra 27 #45-12, Bucaramanga', '2025-09-12 09:14:00'),
(2, 'Laura', 'Mejia', 'laura.mejia@correo.com', '$2y$10$mR4fV8sTqZ1nXc7dPwEuLeYb3kJhGvNaQxCzRtUiOpAsDfGhJkLmN', 'Calle 93 #11-27, Bogota', '2025-09-25 17:42:00'),
(3, 'Carlos', 'Rueda', 'carlos.rueda@correo.com', '$2y$10$aB1cD2eF3gH4iJ5kL6mN7oP8qR9sT0uV1wX2yZ3aB4cD5eF6gH7iJ', 'Cra 43A #18-95, Medellin', '2025-11-02 12:03:00'),
(4, 'Diana', 'Ospina', 'diana.ospina@correo.com', '$2y$10$kL9mN8oP7qR6sT5uV4wX3yZ2aB1cD0eF9gH8iJ7kL6mN5oP4qR3sT', 'Calle 36 #22-40, Piedecuesta', '2025-12-18 08:27:00'),
(5, 'Julian', 'Barrera', 'julian.barrera@correo.com', '$2y$10$zY9xW8vU7tS6rQ5pO4nM3lK2jI1hG0fE9dC8bA7zY6xW5vU4tS3rQ', 'Av Quebradaseca #15-33, Bucaramanga', '2026-01-22 19:55:00'),
(6, 'Paola', 'Guerrero', 'paola.guerrero@correo.com', '$2y$10$qW2eR3tY4uI5oP6aS7dF8gH9jK0lZ1xC2vB3nM4qW5eR6tY7uI8oP', 'Calle 100 #19-54, Bogota', '2026-03-14 10:31:00'),
(7, 'Mauricio', 'Pineda', 'mauricio.pineda@correo.com', '$2y$10$lP0oI9uY8tR7eW6qA5sD4fG3hJ2kL1zX0cV9bN8mQ7wE6rT5yU4iO', 'Cra 70 #44-21, Medellin', '2026-05-08 21:12:00'),
(8, 'Sofia', 'Valencia', 'sofia.valencia@correo.com', '$2y$10$hG7fD6sA5pO4iU3yT2rE1wQ0zX9cV8bN7mK6jH5gF4dS3aP2oI1uY', 'Cra 33 #52-18, Floridablanca', '2026-07-19 15:47:00');

-- ventas
INSERT INTO ventas (id_venta, id_cliente, fecha_venta, estado) VALUES
(1, 1, '2025-10-14 10:23:00', 'Entregado'),
(2, 2, '2025-11-03 15:40:00', 'Entregado'),
(3, 1, '2025-11-28 09:05:00', 'Entregado'),
(4, 3, '2025-12-15 20:11:00', 'Entregado'),
(5, 4, '2026-01-09 11:47:00', 'Entregado'),
(6, 2, '2026-02-20 16:30:00', 'Entregado'),
(7, 5, '2026-04-05 19:22:00', 'Enviado'),
(8, 6, '2026-06-18 13:15:00', 'Entregado'),
(9, 1, '2026-08-02 21:50:00', 'Procesando'),
(10, 7, '2026-09-05 08:35:00', 'Cancelado');

-- detalle de ventas
INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
(1, 1, 1, 3100000),
(1, 2, 2, 85000),
(2, 5, 3, 55000),
(2, 6, 1, 145000),
(3, 3, 1, 320000),
(3, 4, 1, 240000),
(4, 7, 1, 480000),
(4, 8, 2, 190000),
(5, 9, 2, 110000),
(5, 10, 1, 260000),
(6, 1, 1, 3200000),
(7, 2, 1, 85000),
(7, 3, 2, 320000),
(8, 5, 2, 55000),
(8, 9, 1, 110000),
(8, 2, 1, 85000),
(9, 7, 1, 480000),
(9, 4, 2, 240000),
(10, 6, 2, 145000);


-- ACTUALIZAR TOTALES

UPDATE ventas v
SET v.total = (
    SELECT SUM(d.cantidad * d.precio_unitario_congelado)
    FROM detalle_ventas d
    WHERE d.id_venta = v.id_venta
);



-- PROBAR TODO 

SELECT 'categorias' AS tabla, COUNT(*) AS total FROM categorias
UNION ALL SELECT 'proveedores', COUNT(*) FROM proveedores
UNION ALL SELECT 'productos', COUNT(*) FROM productos
UNION ALL SELECT 'clientes', COUNT(*) FROM clientes
UNION ALL SELECT 'ventas', COUNT(*) FROM ventas
UNION ALL SELECT 'detalle_ventas', COUNT(*) FROM detalle_ventas;

SELECT v.id_venta, c.nombre, c.apellido, v.fecha_venta, v.estado, v.total
FROM ventas v
JOIN clientes c ON c.id_cliente = v.id_cliente
ORDER BY v.fecha_venta;
