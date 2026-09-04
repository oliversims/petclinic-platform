# ADR-0003: Shared RDS instance for all services

**Status:** Accepted
**Date:** 2026-09-02

## Context
Three of the eight services store data: customers, visits, and vets. Strict microservice
practice gives each service its own database so schemas can evolve independently.

The upstream Spring Petclinic schema does not honour that boundary — the `visits` table
has a foreign key to `pets`, which belongs to the customers service.

## Decision
One `db.t4g.micro` RDS MySQL instance with a single `petclinic` database, shared by all
three data services.

Separate instances would triple the cost, and separate databases on one instance would
break the existing foreign keys or require rewriting the application, which this repo
treats as read-only.

## Consequences
**Positive**

- One instance to back up, patch, monitor, and pay for.
- The application's foreign keys work without modification.
- Fits inside the RDS free tier.

**Negative**

- Not a true microservice data boundary; a schema change can affect three services.
- A single point of failure for all three, made sharper by the single-AZ decision
  ([ADR-0006](./0006-single-az-rds.md)).
- One noisy service can exhaust connections for the others.
- Migrating to per-service databases later means untangling the cross-service foreign
  keys first.

