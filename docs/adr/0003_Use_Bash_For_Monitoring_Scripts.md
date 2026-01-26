# ADR-0003: Use Bash for Monitoring Scripts

## Status

Accepted

## Context

We need to create monitoring scripts that:
- Query databases (PostgreSQL)
- Make HTTP requests to APIs
- Check file freshness
- Send alerts (email)
- Integrate with system tools

## Decision

We will use Bash scripts for monitoring, leveraging system tools and common libraries from OSM-Notes-Common.

## Consequences

### Positive

- **System integration**: Excellent integration with PostgreSQL (psql), curl, etc.
- **Consistency**: Same language as other OSM-Notes projects
- **Code reuse**: Can use common libraries from OSM-Notes-Common
- **No dependencies**: Bash is available on all Linux systems
- **Simple deployment**: No runtime dependencies to install
- **Easy debugging**: Standard shell debugging tools

### Negative

- **Error handling**: Bash error handling can be verbose
- **Complexity**: Complex scripts can be hard to maintain
- **Testing**: Less mature testing frameworks
- **Type safety**: No compile-time validation

## Alternatives Considered

### Alternative 1: Python

- **Description**: Use Python for monitoring scripts
- **Pros**: Rich ecosystem, better error handling, easier testing
- **Cons**: Requires Python installation, inconsistent with other projects
- **Why not chosen**: Bash provides consistency with other projects and sufficient capabilities

### Alternative 2: Node.js

- **Description**: Use Node.js/JavaScript for monitoring
- **Pros**: Modern language, good async support, large ecosystem
- **Cons**: Requires Node.js installation, inconsistent with other projects
- **Why not chosen**: Bash is more consistent with ecosystem and sufficient for monitoring needs

### Alternative 3: Monitoring tools (Nagios, Zabbix)

- **Description**: Use dedicated monitoring tools
- **Pros**: Professional tools, rich features, built-in alerting
- **Cons**: Additional infrastructure, learning curve, may be overkill
- **Why not chosen**: Custom scripts provide better integration with OSM-Notes ecosystem

## References

- [Monitoring Scripts](../bin/monitor/)
- [OSM-Notes-Common Libraries](../../OSM-Notes-Common/)
