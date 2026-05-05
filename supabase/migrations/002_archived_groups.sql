-- Migration: add archived flag to groups so users can hide old/inactive groups.
-- Safe to run on a live database — defaults to false, so existing groups stay visible.

alter table groups add column if not exists archived boolean not null default false;
