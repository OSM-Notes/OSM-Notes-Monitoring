# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Maintenance

- Regular code reviews
- Update dependencies
- Security patches
- Performance optimization
- Documentation updates
- Add new monitoring checks as needed
- Improve alert thresholds based on experience
- Optimize queries based on usage
- Add new dashboards as needed

## [1.1.0] - 2026-01-09

### Added

#### Phase 1: Daemon Process Monitoring (High Priority)
- **Daemon metrics collection** (`bin/monitor/collectDaemonMetrics.sh`)
  - Systemd service status monitoring
  - Process information (PID, uptime, memory, CPU)
  - Lock file verification
  - Cycle metrics parsing from logs (duration, success rate, frequency)
  - Processing metrics (notes processed, new vs updated, comments)
- **SQL queries** (`sql/ingestion/daemon_metrics.sql`)
- **Grafana dashboard** (`dashboards/grafana/daemon_overview.json`) - 9 panels
- **Unit tests** (`tests/unit/monitor/test_collectDaemonMetrics.sh`, `test_monitorIngestion_daemon.sh`)
- **Documentation** (updated `docs/INGESTION_METRICS.md`)

#### Phase 2: Advanced Database Performance Monitoring (High Priority)
- **Database metrics collection** (`bin/monitor/collectDatabaseMetrics.sh`)
  - Table sizes and growth tracking
  - Index usage and bloat analysis
  - Unused indexes detection
  - Slow queries tracking
  - Cache hit ratio monitoring
  - Connection statistics
  - Lock statistics
- **SQL queries** (`sql/ingestion/database_performance_advanced.sql`)
- **Grafana dashboard** (`dashboards/grafana/database_performance.json`) - 11 panels
- **Unit tests** (`tests/unit/monitor/test_collectDatabaseMetrics.sh`, `test_monitorIngestion_database.sh`)
- **Documentation** (updated `docs/INGESTION_METRICS.md`)

#### Phase 3: Complete System Resources Monitoring (Medium Priority)
- **System metrics collection** (`bin/monitor/collectSystemMetrics.sh`)
  - Load average monitoring
  - CPU usage by process (daemon, PostgreSQL)
  - Memory usage by process
  - Swap usage
  - Disk I/O statistics
  - Network traffic monitoring
- **Integration** (`bin/monitor/monitorInfrastructure.sh`)
- **Grafana dashboard** (`dashboards/grafana/system_resources.json`) - 10 panels
- **Unit tests** (`tests/unit/monitor/test_collectSystemMetrics.sh`, `test_monitorInfrastructure_system.sh`)
- **Documentation** (updated `docs/INFRASTRUCTURE_MONITORING_GUIDE.md`)

#### Phase 4: Enhanced API Integration Metrics (Medium Priority)
- **API logs parser** (`bin/lib/parseApiLogs.sh`)
  - HTTP request parsing
  - Response time extraction
  - Success/failure rate calculation
  - Rate limit detection
  - Error classification (4xx, 5xx)
  - Synchronization gap detection
- **SQL queries** (`sql/ingestion/api_metrics.sql`)
- **Grafana dashboard** (`dashboards/grafana/api_integration.json`) - 10 panels
- **Unit tests** (`tests/unit/lib/test_parseApiLogs.sh`, `test_monitorIngestion_api_advanced.sh`)
- **Documentation** (updated `docs/INGESTION_METRICS.md`)

#### Phase 5: Boundary Processing Monitoring (Low Priority)
- **Boundary metrics collection** (`bin/monitor/collectBoundaryMetrics.sh`)
  - Countries and maritime boundaries last update tracking
  - Update frequency calculation
  - Notes without country detection
  - Notes with wrong country assignment detection (referential integrity + spatial mismatch)
  - Notes affected by boundary changes detection
- **SQL queries** (`sql/ingestion/boundary_metrics.sql`)
- **Grafana dashboard** (`dashboards/grafana/boundary_processing.json`) - 7 panels
- **Unit tests** (`tests/unit/monitor/test_collectBoundaryMetrics.sh`, `test_monitorIngestion_boundary.sh`)
- **Documentation** (updated `docs/INGESTION_METRICS.md`)

#### Phase 6: Structured Log Analysis Metrics (Medium Priority)
- **Structured logs parser** (`bin/lib/parseStructuredLogs.sh`)
  - Cycle metrics extraction (duration, frequency, success rate)
  - Processing metrics (notes, comments, rates)
  - Stage timing metrics from [TIMING] logs
  - Optimization metrics (ANALYZE cache effectiveness, integrity optimizations, sequence syncs)
- **Grafana dashboard** (`dashboards/grafana/log_analysis.json`) - 14 panels
- **Unit tests** (`tests/unit/lib/test_parseStructuredLogs.sh`, `test_monitorIngestion_log_analysis.sh`)
- **Documentation** (updated `docs/INGESTION_METRICS.md`)

### Changed

- **Enhanced `monitorIngestion.sh`** with new check functions:
  - `check_daemon_metrics()` - Phase 1
  - `check_advanced_database_metrics()` - Phase 2
  - `check_advanced_system_metrics()` - Phase 3 (in `monitorInfrastructure.sh`)
  - `check_advanced_api_metrics()` - Phase 4
  - `check_boundary_metrics()` - Phase 5
  - `check_structured_log_metrics()` - Phase 6
- **Updated configuration** (`config/monitoring.conf.example`):
  - Added thresholds for daemon monitoring
  - Added thresholds for advanced database monitoring
  - Added thresholds for system resources
  - Added thresholds for API monitoring
  - Added thresholds for boundary processing
  - Added thresholds for log analysis
- **Documentation updates**:
  - `docs/INGESTION_METRICS.md` - Added 60+ new metrics
  - `docs/INFRASTRUCTURE_MONITORING_GUIDE.md` - Added system resources metrics
  - All metrics properly documented with descriptions, units, thresholds, and alert conditions

### Technical Details

- **Total new metrics**: 60+ metrics across 6 phases
- **New scripts**: 6 collection scripts, 2 parser libraries
- **New dashboards**: 6 Grafana dashboards
- **New SQL queries**: 3 SQL files with 30+ queries
- **Test coverage**: 30+ new unit tests, all passing
- **Configuration options**: 15+ new configurable thresholds

### Notes

- All 6 phases of the monitoring enhancement plan have been successfully implemented
- See `docs/INGESTION_METRICS.md` for complete metric documentation
- See `docs/INGESTION_MONITORING_GUIDE.md` for operational guidance

## [1.0.0] - 2026-01-09

### Added

- Complete monitoring system for all OSM Notes components
- Ingestion monitoring scripts (`bin/monitor/monitorIngestion.sh`)
- Analytics monitoring scripts (`bin/monitor/monitorAnalytics.sh`)
- WMS monitoring scripts (`bin/monitor/monitorWMS.sh`)
- Data freshness monitoring (`bin/monitor/monitorData.sh`)
- Infrastructure monitoring (`bin/monitor/monitorInfrastructure.sh`)
- API security monitoring (`bin/monitor/monitorAPI.sh`)
- Rate limiting implementation (`bin/security/rateLimiter.sh`)
- DDoS protection (`bin/security/ddosProtection.sh`)
- Abuse detection (`bin/security/abuseDetection.sh`)
- IP blocking management (`bin/security/ipBlocking.sh`)
- Unified alerting system (`bin/alerts/`)
- Grafana dashboards (6 dashboards)
- HTML dashboards (3 dashboards)
- Comprehensive test suite (>80% coverage)
- Complete documentation (50+ guides and references)

### Changed

- All planned features from v0.1.0 have been implemented
- System ready for production deployment

## [0.1.0] - 2025-12-24

### Added

- Repository structure
- Documentation:
  - Monitoring Architecture Proposal
  - API Security Design
  - Monitoring Resumen Ejecutivo (Spanish)
- README.md with project overview
- CHANGELOG.md
- .gitignore
- LICENSE (GPL v3)

---

[Unreleased]: https://github.com/OSMLatam/OSM-Notes-Monitoring/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/OSMLatam/OSM-Notes-Monitoring/releases/tag/v1.0.0
[0.1.0]: https://github.com/OSMLatam/OSM-Notes-Monitoring/releases/tag/v0.1.0

