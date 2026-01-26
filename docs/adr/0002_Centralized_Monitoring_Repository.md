# ADR-0002: Centralized Monitoring Repository

## Status

Accepted

## Context

Monitoring scripts and checks are scattered across multiple repositories. We need a way to:
- Provide unified visibility of system health
- Monitor cross-repository dependencies
- Centralize alerting
- Protect API from abuse
- Track data freshness across all sources

## Decision

We will create a separate repository (OSM-Notes-Monitoring) for centralized monitoring, alerting, and security.

## Consequences

### Positive

- **Unified visibility**: Single dashboard for all components
- **Cross-repository monitoring**: Can monitor dependencies between repos
- **Centralized alerting**: Unified alert system with escalation
- **API protection**: Rate limiting, DDoS protection, abuse detection
- **Data freshness**: Centralized checks for all data sources
- **Separation of concerns**: Monitoring logic separated from application logic
- **Independent evolution**: Monitoring can evolve independently

### Negative

- **Additional repository**: One more repository to maintain
- **Dependency on all projects**: Requires access to all monitored components
- **Complexity**: More complex architecture
- **Deployment dependency**: Must be deployed after other projects

## Alternatives Considered

### Alternative 1: Monitoring in each repository

- **Description**: Keep monitoring scripts in each repository
- **Pros**: Co-located with code, simpler architecture
- **Cons**: No unified visibility, duplicate monitoring logic, hard to track dependencies
- **Why not chosen**: Centralized monitoring provides better visibility and management

### Alternative 2: External monitoring service (Prometheus, Grafana)

- **Description**: Use external monitoring services
- **Pros**: Professional tools, rich features, good visualization
- **Cons**: Additional infrastructure, learning curve, may be overkill
- **Why not chosen**: Custom monitoring provides better integration with OSM-Notes ecosystem

### Alternative 3: Monitoring as part of Common

- **Description**: Include monitoring in OSM-Notes-Common
- **Pros**: One less repository, shared with common libraries
- **Cons**: Mixes concerns, Common should be libraries only
- **Why not chosen**: Monitoring is not a library, it's a separate system

## References

- [Monitoring Architecture Proposal](Monitoring_Architecture_Proposal.md)
- [README](../README.md)
