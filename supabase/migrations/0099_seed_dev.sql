
-- Esta migración solo debe ejecutarse en entornos de desarrollo o pruebas.
-- Realizamos una verificación defensiva para evitar que se ejecute accidentalmente
-- sobre una base de datos de producción.
do $$
declare
    v_db_name text := current_database();
    v_is_safe boolean;
begin
    v_is_safe := v_db_name ilike '%dev%'
        or v_db_name ilike '%develop%'
        or v_db_name ilike '%test%'
        or v_db_name ilike '%local%'
        or v_db_name ilike '%staging%';

    if not v_is_safe then
        raise exception '0099_seed_dev.sql solo puede ejecutarse en bases de datos de desarrollo/pruebas. Base de datos actual: %', v_db_name;
    end if;
end $$;

-- Función auxiliar para generar citas de prueba
create or replace function public.generate_test_appointments(
    p_days_back int default 90,
    p_days_forward int default 30,
    p_appointments_per_day int default 8
)
returns void
language plpgsql
as $$
declare
    v_date date;
    v_start_time timestamptz;
    v_service record;
    v_profile record;
    v_hour int;
    v_status text;
    v_counter int := 0;
    v_db_name text := current_database();
    v_is_safe boolean;
begin
    v_is_safe := v_db_name ilike '%dev%'
        or v_db_name ilike '%develop%'
        or v_db_name ilike '%test%'
        or v_db_name ilike '%local%'
        or v_db_name ilike '%staging%';

    if not v_is_safe then
        raise exception 'generate_test_appointments() solo está disponible en entornos de desarrollo/pruebas. Base de datos actual: %', v_db_name;
    end if;

    -- Iterar sobre los días
    for v_date in
    select generate_series(
        current_date - (p_days_back || ' days')::interval,
        current_date + (p_days_forward || ' days')::interval,
        '1 day'::interval
    )::date
    loop
    -- Saltar domingos
    if extract(dow from v_date) = 0 then
        continue;
    end if;

    -- Generar citas para este día
    for i in 1..p_appointments_per_day loop
        -- Seleccionar servicio aleatorio
        select * into v_service
        from public.services
        order by random()
        limit 1;

        -- Seleccionar cliente aleatorio (solo leads)
        select * into v_profile
        from public.profiles
        where role = 'lead'
        order by random()
        limit 1;

        -- Hora aleatoria entre 9:00 y 18:00
        v_hour := 9 + floor(random() * 9)::int;
        v_start_time := v_date + (v_hour || ' hours')::interval;

        -- Estado según la fecha
        if v_date < current_date then
            -- Citas pasadas: 85% confirmed, 10% cancelled, 5% pending
            v_status := case
                when random() < 0.85 then 'confirmed'
                when random() < 0.95 then 'cancelled'
                else 'pending'
            end;
        elsif v_date = current_date then
            -- Hoy: 90% confirmadas, 10% pending
            v_status := case
                when random() < 0.9 then 'confirmed'
                else 'pending'
            end;
        else
            -- Futuras: 70% confirmadas, 30% pending
            v_status := case
                when random() < 0.7 then 'confirmed'
                else 'pending'
            end;
        end if;

        -- Insertar cita
        insert into public.appointments (
            profile_id, service_id, status, start_time, end_time, notes
        ) values (
            v_profile.id,
            v_service.id,
            v_status::public.appointment_status,
            v_start_time,
            v_start_time + (v_service.duration_minutes || ' minutes')::interval,
            case
                when random() < 0.3 then 'Primera visita'
                when random() < 0.5 then 'Cliente regular'
                else null
            end
        );
        v_counter := v_counter + 1;

        if v_counter >= 10000 then
            raise notice 'Generadas % citas, límite alcanzado', v_counter;
            return;
        end if;
    end loop;
    end loop;
    raise notice 'Generadas % citas de prueba', v_counter;
end $$;


-- INSERTS DE DATOS (Servicios, Recursos, Perfiles, Inventario, KB, Cross-sell)
insert into public.services (name, description, base_price, duration_minutes, metadata) values
('Limpieza Facial Básica', 'Limpieza profunda con extracción de comedones', 45.00, 60, '{"category": "facial", "popularity": "high"}'),
('Limpieza Facial Premium', 'Limpieza profunda + hidratación + mascarilla', 75.00, 90, '{"category": "facial", "popularity": "high"}'),
('Peeling Químico', 'Exfoliación química suave para renovación celular', 120.00, 75, '{"category": "facial", "popularity": "medium"}'),
('Microdermoabrasión', 'Tratamiento mecánico de exfoliación', 95.00, 60, '{"category": "facial", "popularity": "medium"}'),
('Tratamiento Anti-Edad', 'Protocolo completo anti-envejecimiento', 180.00, 120, '{"category": "facial", "popularity": "high"}'),
('Depilación Láser - Zona Pequeña', 'Axilas, labio superior, bikini línea', 35.00, 30, '{"category": "depilacion", "popularity": "high"}'),
('Depilación Láser - Zona Media', 'Brazos, piernas media', 65.00, 45, '{"category": "depilacion", "popularity": "high"}'),
('Depilación Láser - Zona Grande', 'Piernas completas, espalda completa', 120.00, 90, '{"category": "depilacion", "popularity": "medium"}'),
('Masaje Relajante', 'Masaje corporal completo 60 minutos', 70.00, 60, '{"category": "corporal", "popularity": "high"}'),
('Masaje Descontracturante', 'Masaje terapéutico focalizado', 85.00, 75, '{"category": "corporal", "popularity": "medium"}'),
('Drenaje Linfático', 'Técnica manual para reducir retención de líquidos', 90.00, 60, '{"category": "corporal", "popularity": "medium"}'),
('Radiofrecuencia Corporal', 'Tratamiento reafirmante con radiofrecuencia', 150.00, 90, '{"category": "corporal", "popularity": "high"}'),
('Presoterapia', 'Drenaje mecánico con botas de presión', 60.00, 45, '{"category": "corporal", "popularity": "medium"}'),
('Cavitación Ultrasónica', 'Reducción de grasa localizada con ultrasonido', 110.00, 60, '{"category": "corporal", "popularity": "high"}'),
('Manicura Express', 'Limado, cutículas y esmaltado', 25.00, 30, '{"category": "manos_pies", "popularity": "high"}'),
('Manicura Spa', 'Tratamiento completo con exfoliación e hidratación', 40.00, 60, '{"category": "manos_pies", "popularity": "medium"}'),
('Pedicura Completa', 'Tratamiento completo de pies con masaje', 45.00, 60, '{"category": "manos_pies", "popularity": "high"}'),
('Diseño de Cejas', 'Perfilado y diseño profesional de cejas', 20.00, 30, '{"category": "cejas_pestanas", "popularity": "high"}'),
('Tinte de Cejas', 'Coloración semipermanente de cejas', 15.00, 20, '{"category": "cejas_pestanas", "popularity": "medium"}'),
('Lifting de Pestañas', 'Permanente de pestañas con tinte', 55.00, 60, '{"category": "cejas_pestanas", "popularity": "high"}')
on conflict do nothing;

insert into public.resources (name, type, status, metadata) values
('Sala 1 - Tratamientos Faciales', 'room', 'available', '{"capacity": 1, "floor": 1}'),
('Sala 2 - Tratamientos Faciales', 'room', 'available', '{"capacity": 1, "floor": 1}'),
('Sala 3 - Depilación Láser', 'room', 'available', '{"capacity": 1, "floor": 2}'),
('Sala 4 - Masajes', 'room', 'available', '{"capacity": 1, "floor": 2}'),
('Sala 5 - Tratamientos Corporales', 'room', 'available', '{"capacity": 1, "floor": 2}'),
('Sala 6 - Manicura/Pedicura', 'room', 'available', '{"capacity": 2, "floor": 1}'),
('Equipo Láser Diodo #1', 'equipment', 'available', '{"brand": "Soprano ICE", "year": 2023}'),
('Equipo Láser Diodo #2', 'equipment', 'available', '{"brand": "Soprano ICE", "year": 2023}'),
('Equipo Radiofrecuencia', 'equipment', 'available', '{"brand": "Venus Legacy", "year": 2022}'),
('Equipo Cavitación', 'equipment', 'available', '{"brand": "UltraShape", "year": 2023}'),
('Equipo Presoterapia', 'equipment', 'available', '{"brand": "Pressotherapy Pro", "year": 2022}'),
('Equipo Microdermoabrasión', 'equipment', 'available', '{"brand": "DermaPro", "year": 2021}'),
('Dra. Ana García - Dermatóloga', 'staff', 'available', '{"specialty": "dermatologia", "license": "ABC123"}'),
('Lic. María López - Esteticista', 'staff', 'available', '{"specialty": "facial", "experience_years": 5}'),
('Lic. Carmen Ruiz - Esteticista', 'staff', 'available', '{"specialty": "corporal", "experience_years": 8}'),
('Lic. Laura Martín - Masajista', 'staff', 'available', '{"specialty": "masajes", "experience_years": 6}'),
('Tec. Pedro Sánchez - Láser', 'staff', 'available', '{"specialty": "depilacion_laser", "experience_years": 4}'),
('Tec. Julia Fernández - Manicurista', 'staff', 'available', '{"specialty": "manos_pies", "experience_years": 3}')
on conflict do nothing;

insert into public.service_resource_requirements (service_id, resource_id, quantity)
select s.id, r.id, 1 from public.services s cross join public.resources r
where s.name in ('Limpieza Facial Básica', 'Limpieza Facial Premium', 'Peeling Químico', 'Tratamiento Anti-Edad')
and r.name in ('Sala 1 - Tratamientos Faciales', 'Lic. María López - Esteticista')
on conflict do nothing;
insert into public.service_resource_requirements (service_id, resource_id, quantity)
select s.id, r.id, 1 from public.services s cross join public.resources r
where s.name = 'Microdermoabrasión' and r.name in ('Sala 1 - Tratamientos Faciales', 'Equipo Microdermoabrasión', 'Lic. María López - Esteticista')
on conflict do nothing;
insert into public.service_resource_requirements (service_id, resource_id, quantity)
select s.id, r.id, 1 from public.services s cross join public.resources r
where s.name like 'Depilación Láser%' and r.name in ('Sala 3 - Depilación Láser', 'Equipo Láser Diodo #1', 'Tec. Pedro Sánchez - Láser')
on conflict do nothing;
insert into public.service_resource_requirements (service_id, resource_id, quantity)
select s.id, r.id, 1 from public.services s cross join public.resources r
where s.name in ('Masaje Relajante', 'Masaje Descontracturante', 'Drenaje Linfático') and r.name in ('Sala 4 - Masajes', 'Lic. Laura Martín - Masajista')
on conflict do nothing;
insert into public.service_resource_requirements (service_id, resource_id, quantity)
select s.id, r.id, 1 from public.services s cross join public.resources r
where s.name = 'Radiofrecuencia Corporal' and r.name in ('Sala 5 - Tratamientos Corporales', 'Equipo Radiofrecuencia', 'Lic. Carmen Ruiz - Esteticista')
on conflict do nothing;
insert into public.service_resource_requirements (service_id, resource_id, quantity)
select s.id, r.id, 1 from public.services s cross join public.resources r
where s.name = 'Cavitación Ultrasónica' and r.name in ('Sala 5 - Tratamientos Corporales', 'Equipo Cavitación', 'Lic. Carmen Ruiz - Esteticista')
on conflict do nothing;
insert into public.service_resource_requirements (service_id, resource_id, quantity)
select s.id, r.id, 1 from public.services s cross join public.resources r
where s.name = 'Presoterapia' and r.name in ('Sala 5 - Tratamientos Corporales', 'Equipo Presoterapia', 'Lic. Carmen Ruiz - Esteticista')
on conflict do nothing;
insert into public.service_resource_requirements (service_id, resource_id, quantity)
select s.id, r.id, 1 from public.services s cross join public.resources r
where s.name in ('Manicura Express', 'Manicura Spa', 'Pedicura Completa') and r.name in ('Sala 6 - Manicura/Pedicura', 'Tec. Julia Fernández - Manicurista')
on conflict do nothing;
insert into public.service_resource_requirements (service_id, resource_id, quantity)
select s.id, r.id, 1 from public.services s cross join public.resources r
where s.name in ('Diseño de Cejas', 'Tinte de Cejas', 'Lifting de Pestañas') and r.name in ('Sala 2 - Tratamientos Faciales', 'Lic. María López - Esteticista')
on conflict do nothing;

insert into public.profiles (phone_number, role, name, email, metadata) values
('+34600000001', 'owner', 'Admin Principal', 'admin@clinica.com', '{"is_admin": true}'),
('+34600000002', 'owner', 'Recepcionista', 'recepcion@clinica.com', '{"department": "front_desk"}'),
('+34611111111', 'lead', 'Laura Gómez', 'laura.gomez@email.com', '{"preferred_contact": "whatsapp"}'),
('+34622222222', 'lead', 'Carlos Martínez', 'carlos.martinez@email.com', '{"preferred_contact": "sms"}'),
('+34633333333', 'lead', 'Ana Silva', 'ana.silva@email.com', '{"preferred_contact": "whatsapp"}'),
('+34644444444', 'lead', 'Roberto Díaz', 'roberto.diaz@email.com', '{"preferred_contact": "email"}'),
('+34655555555', 'lead', 'Isabel Torres', 'isabel.torres@email.com', '{"preferred_contact": "whatsapp"}'),
('+34666666666', 'lead', 'Miguel Ángel Ruiz', 'miguel.ruiz@email.com', '{"preferred_contact": "whatsapp"}'),
('+34677777777', 'lead', 'Patricia Moreno', 'patricia.moreno@email.com', '{"preferred_contact": "sms"}'),
('+34688888888', 'lead', 'David Romero', 'david.romero@email.com', '{"preferred_contact": "whatsapp"}')
on conflict do nothing;

insert into public.inventory (sku, name, quantity, reorder_threshold, price, metadata) values
('CREMA-HID-001', 'Crema Hidratante Premium 50ml', 45, 15, 28.50, '{"brand": "DermaLux", "category": "facial"}'),
('SERUM-VIT-C', 'Serum Vitamina C 30ml', 30, 10, 42.00, '{"brand": "VitaSkin", "category": "facial"}'),
('MASCARILLA-ARC', 'Mascarilla Arcilla Verde 250ml', 20, 8, 15.00, '{"brand": "NaturalCare", "category": "facial"}'),
('GEL-LASER-500', 'Gel Conductor Láser 500ml', 12, 5, 18.00, '{"brand": "LaserPro", "category": "depilacion"}'),
('ACEITE-MASAJE', 'Aceite de Masaje Neutro 1L', 25, 10, 22.00, '{"brand": "RelaxOil", "category": "masajes"}'),
('CREMA-CORPORAL', 'Crema Reafirmante Corporal 200ml', 18, 8, 35.00, '{"brand": "BodyFirm", "category": "corporal"}'),
('ESMALTE-BASE', 'Esmalte Base Fortalecedor', 50, 20, 8.50, '{"brand": "NailPro", "category": "manos_pies"}'),
('ESMALTE-TOP', 'Top Coat Brillo Extremo', 50, 20, 9.00, '{"brand": "NailPro", "category": "manos_pies"}'),
('QUITAESMALTE', 'Quitaesmalte Sin Acetona 250ml', 8, 5, 6.50, '{"brand": "NailCare", "category": "manos_pies"}'),
('TINTE-CEJAS-MARRON', 'Tinte Cejas Marrón', 15, 5, 12.00, '{"brand": "BrowPerfect", "category": "cejas"}'),
('TINTE-CEJAS-NEGRO', 'Tinte Cejas Negro', 15, 5, 12.00, '{"brand": "BrowPerfect", "category": "cejas"}'),
('KIT-LIFTING-PEST', 'Kit Lifting Pestañas', 8, 3, 45.00, '{"brand": "LashLift", "category": "pestanas"}'),
('GUANTES-LAT-M', 'Guantes Látex Medianos (caja 100)', 5, 2, 18.00, '{"category": "consumibles"}'),
('TOALLAS-DESECH', 'Toallas Desechables (rollo 80)', 10, 4, 12.00, '{"category": "consumibles"}'),
('SABANAS-CAMILLA', 'Sábanas Camilla Desechables (rollo 100)', 8, 3, 15.00, '{"category": "consumibles"}')
on conflict do nothing;

insert into public.knowledge_base (category, question, answer, metadata) values
('servicios', '¿Qué tratamientos faciales ofrecen?', 'Ofrecemos limpieza facial básica y premium, peeling químico, microdermoabrasión y tratamientos anti-edad. Cada uno está diseñado para diferentes necesidades de la piel.', '{"keywords": ["facial", "tratamientos", "piel"]}'),
('servicios', '¿Cuánto cuesta la depilación láser?', 'La depilación láser tiene diferentes precios según la zona: zonas pequeñas (axilas, labio) desde 35€, zonas medias (brazos) desde 65€, y zonas grandes (piernas completas) desde 120€.', '{"keywords": ["depilacion", "laser", "precio"]}'),
('servicios', '¿Cuántas sesiones necesito de depilación láser?', 'Generalmente se necesitan entre 6-8 sesiones para resultados óptimos, con intervalos de 4-6 semanas entre sesiones. El número exacto depende del tipo de piel y vello.', '{"keywords": ["sesiones", "depilacion", "laser"]}'),
('citas', '¿Cómo puedo agendar una cita?', 'Puedes agendar tu cita por WhatsApp, llamando al teléfono de la clínica, o a través de nuestra plataforma online. Te mostraremos los horarios disponibles.', '{"keywords": ["agendar", "cita", "reserva"]}'),
('citas', '¿Cuál es la política de cancelación?', 'Puedes cancelar o reprogramar tu cita con al menos 24 horas de anticipación sin cargo. Cancelaciones con menos tiempo pueden tener un cargo del 50%.', '{"keywords": ["cancelacion", "politica", "reprogramar"]}'),
('preparacion', '¿Cómo me preparo para la depilación láser?', 'No tomes sol 2 semanas antes, afeita la zona 24h antes del tratamiento, evita cremas o perfumes el día de la sesión, y no depiles con cera o pinzas 4 semanas antes.', '{"keywords": ["preparacion", "depilacion", "laser"]}'),
('preparacion', '¿Qué debo hacer antes de un tratamiento facial?', 'Llega con la piel limpia sin maquillaje. Evita exfoliantes o ácidos 48h antes. Informa sobre alergias o productos que estés usando.', '{"keywords": ["preparacion", "facial", "tratamiento"]}'),
('ubicacion', '¿Dónde están ubicados?', 'Estamos en el centro de Madrid, en la Calle Gran Vía 123. Muy cerca del metro Callao. Tenemos horario de lunes a sábado de 9:00 a 20:00.', '{"keywords": ["ubicacion", "direccion", "horario"]}'),
('pago', '¿Qué métodos de pago aceptan?', 'Aceptamos efectivo, tarjetas de crédito/débito, transferencia bancaria y Bizum. También ofrecemos planes de pago para tratamientos largos.', '{"keywords": ["pago", "metodos", "tarjeta"]}'),
('promociones', '¿Tienen promociones o descuentos?', 'Sí, tenemos bonos de sesiones con descuento, promociones mensuales y descuento de 10% para estudiantes. Pregunta por nuestras ofertas actuales.', '{"keywords": ["promociones", "descuentos", "ofertas"]}'),
('resultados', '¿Cuándo veré resultados del tratamiento anti-edad?', 'Los resultados son progresivos. Notarás mejoras desde la primera sesión, pero el efecto completo se ve tras 4-6 sesiones. Recomendamos un mantenimiento mensual.', '{"keywords": ["resultados", "antiedad", "sesiones"]}'),
('contraindicaciones', '¿Quiénes no pueden hacerse depilación láser?', 'No recomendamos el láser si estás embarazada, con piel bronceada recientemente, con infecciones activas en la zona, o si tomas ciertos medicamentos fotosensibilizantes.', '{"keywords": ["contraindicaciones", "laser", "embarazo"]}')
on conflict do nothing;

insert into public.cross_sell_rules (trigger_service_id, recommended_service_id, message_template, priority)
select s1.id, s2.id, 'Después de tu {trigger_service}, te recomendamos complementar con {recommended_service} para mejores resultados.', 1
from public.services s1 cross join public.services s2
where (s1.name = 'Limpieza Facial Básica' and s2.name = 'Tratamiento Anti-Edad')
or (s1.name = 'Depilación Láser - Zona Pequeña' and s2.name = 'Tratamiento Anti-Edad')
or (s1.name = 'Masaje Relajante' and s2.name = 'Drenaje Linfático')
or (s1.name = 'Cavitación Ultrasónica' and s2.name = 'Radiofrecuencia Corporal')
or (s1.name = 'Peeling Químico' and s2.name = 'Limpieza Facial Premium')
or (s1.name = 'Manicura Express' and s2.name = 'Pedicura Completa')
on conflict do nothing;

-- Bloqueos de recursos de prueba
insert into public.resource_blocks (resource_id, start_time, end_time, reason)
select r.id, (current_date + interval '7 days' + time '09:00') as start_time, (current_date + interval '7 days' + time '14:00') as end_time, 'Mantenimiento preventivo programado'
from public.resources r where r.name = 'Equipo Láser Diodo #1' on conflict do nothing;

insert into public.resource_blocks (resource_id, start_time, end_time, reason)
select r.id, (current_date + interval '14 days')::timestamptz as start_time, (current_date + interval '21 days')::timestamptz as end_time, 'Vacaciones programadas'
from public.resources r where r.name = 'Lic. Carmen Ruiz - Esteticista' on conflict do nothing;
