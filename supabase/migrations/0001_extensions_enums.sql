-- Extensiones
create extension if not exists pgcrypto;
create extension if not exists unaccent;
create extension if not exists pg_trgm;
create extension if not exists btree_gist;

-- ENUMs
do $$ begin
create type public.user_role as enum ('owner','lead');
exception when duplicate_object then null; end $$;

do $$ begin
create type public.appointment_status as enum ('pending','confirmed','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
create type public.waitlist_status as enum ('active','notified','converted');
exception when duplicate_object then null; end $$;

-- ENUMs del módulo de recursos (Migración 03)
do $$ begin
create type public.resource_type as enum ('room','equipment','staff');
exception when duplicate_object then null; end $$;

do $$ begin
create type public.resource_status as enum ('available','maintenance','unavailable');
exception when duplicate_object then null; end $$;
