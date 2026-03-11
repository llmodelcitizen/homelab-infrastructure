#!/usr/bin/env python3
"""
Validate Grafana dashboard queries against Prometheus.

Tests all PromQL expressions in a dashboard JSON file by executing them
against a running Prometheus instance.

Usage:
    ./validate-dashboard-queries.py <dashboard.json> [--limit N]

Examples:
    ./validate-dashboard-queries.py ../grafana/provisioning/dashboards/json/node-exporter.json
    ./validate-dashboard-queries.py ../grafana/provisioning/dashboards/json/node-exporter.json --limit 50
"""

import argparse
import json
import socket
import subprocess
import sys
import urllib.parse


def extract_exprs(obj, results=None):
    """Recursively extract all 'expr' fields from a Grafana dashboard JSON."""
    if results is None:
        results = []
    if isinstance(obj, dict):
        if 'expr' in obj and obj['expr']:
            results.append(obj['expr'])
        for v in obj.values():
            extract_exprs(v, results)
    elif isinstance(obj, list):
        for item in obj:
            extract_exprs(item, results)
    return results


def substitute_variables(expr):
    """Replace Grafana template variables with test values."""
    replacements = {
        '$node': 'host.docker.internal:9100',
        '$job': 'node-exporter',
        '$__rate_interval': '5m',
        '$__interval': '1m',
        '$device': '.*',
        '$nodename': socket.gethostname(),
    }
    for var, val in replacements.items():
        expr = expr.replace(var, val)
    return expr.replace('\n', ' ')


def test_query(expr):
    """Test a PromQL query against Prometheus via docker exec."""
    encoded = urllib.parse.quote(expr)
    cmd = f"docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query={encoded}' 2>/dev/null"

    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        if not result.stdout:
            return None, "Empty response"
        data = json.loads(result.stdout)
        if data.get('status') == 'error':
            return False, data.get('error', 'Unknown error')
        return True, None
    except json.JSONDecodeError:
        return None, "Invalid JSON response"
    except subprocess.TimeoutExpired:
        return None, "Query timeout"
    except Exception as e:
        return None, str(e)


def main():
    parser = argparse.ArgumentParser(description='Validate Grafana dashboard queries')
    parser.add_argument('dashboard', help='Path to dashboard JSON file')
    parser.add_argument('--limit', type=int, default=0, help='Limit number of queries to test (0 = all)')
    args = parser.parse_args()

    with open(args.dashboard) as f:
        dashboard = json.load(f)

    exprs = list(set(extract_exprs(dashboard)))  # dedupe
    total = len(exprs)

    if args.limit > 0:
        exprs = exprs[:args.limit]

    print(f"Found {total} unique queries, testing {len(exprs)}...")
    print()

    errors = []
    warnings = []

    for i, expr in enumerate(exprs, 1):
        test_expr = substitute_variables(expr)
        success, error = test_query(test_expr)

        if success is False:
            errors.append((expr[:80], error))
            print(f"[{i}/{len(exprs)}] ERROR: {error[:60]}")
        elif success is None:
            warnings.append((expr[:80], error))
            print(f"[{i}/{len(exprs)}] WARN: {error[:60]}")
        else:
            print(f"[{i}/{len(exprs)}] OK")

    print()
    print(f"Results: {len(exprs) - len(errors) - len(warnings)} OK, {len(errors)} errors, {len(warnings)} warnings")

    if errors:
        print("\nErrors:")
        for expr, error in errors:
            print(f"  Query: {expr}...")
            print(f"  Error: {error}")
            print()

    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
