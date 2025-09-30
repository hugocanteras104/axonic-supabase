-- Comentarios adicionales para tablas clave

-- Comentarios en services
comment on table public.services is 'Catálogo de servicios ofrecidos';
comment on column public.services.base_price is 'Precio base en EUR (sin descuentos)';
comment on column public.services.duration_minutes is 'Duración estimada del servicio';

-- Comentarios en profiles
comment on table public.profiles is 'Usuarios del sistema: clientes (lead) y administradores (owner)';
comment on column public.profiles.phone_number is 'Teléfono único en formato internacional (+34XXXXXXXXX)';
comment on column public.profiles.role is 'Rol: lead (cliente) u owner (administrador)';

-- Comentarios en resources
comment on table public.resources is 'Recursos físicos: salas, equipos y personal';
comment on column public.resources.type is 'Tipo: room (sala), equipment (equipo), staff (personal)';
comment on column public.resources.status is 'Estado: available, maintenance, unavailable';

-- Comentarios en knowledge_base
comment on table public.knowledge_base is 'Base de conocimiento para bot de atención';
comment on column public.knowledge_base.question_normalized is 'Pregunta normalizada para búsqueda eficiente';
comment on column public.knowledge_base.view_count is 'Contador de consultas (popularidad)';

-- Comentarios en waitlists
comment on table public.waitlists is 'Lista de espera cuando no hay disponibilidad';
comment on column public.waitlists.status is 'Estado: active (esperando), notified (avisado), converted (convertido a cita)';

-- Comentarios en inventory
comment on table public.inventory is 'Inventario de productos y consumibles';
comment on column public.inventory.sku is 'Código único del producto (SKU)';
comment on column public.inventory.reorder_threshold is 'Stock mínimo antes de reabastecer';
