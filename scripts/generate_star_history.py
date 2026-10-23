#!/usr/bin/env python3
"""Render a "stargazers over time" chart from the GitHub API.

The README badge used to point at starchart.cc, an external service that
renders the chart on demand. When that service is rate limited every badge it
serves breaks, including ours. This script removes the dependency: the data is
fetched straight from GitHub and the chart is committed to the repository, so
the README renders even if third-party charting services are down.

Standard library only, so no dependencies need to be installed in CI.

Usage:
  GITHUB_TOKEN=... python3 scripts/generate_star_history.py \
    --repo vitobotta/hetzner-k3s --output assets/star-history.svg
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta

API_ROOT = "https://api.github.com"
PER_PAGE = 100
MAX_PAGES = 400

WIDTH = 880
HEIGHT = 420
MARGIN_LEFT = 64
MARGIN_RIGHT = 96
MARGIN_TOP = 56
MARGIN_BOTTOM = 44

LINE_COLOR = "#2f81f7"
AXIS_COLOR = "#d0d7de"
TEXT_COLOR = "#57606a"
TITLE_COLOR = "#1f2328"
BACKGROUND_COLOR = "#ffffff"


def fetch_star_dates(repo, token):
    """Return the UTC dates on which the repository was starred."""
    dates = []
    url = "%s/repos/%s/stargazers?per_page=%d" % (
        API_ROOT,
        urllib.parse.quote(repo),
        PER_PAGE,
    )

    for _ in range(MAX_PAGES):
        request = urllib.request.Request(url)
        request.add_header("Accept", "application/vnd.github.star+json")
        request.add_header("User-Agent", "hetzner-k3s-star-history")
        if token:
            request.add_header("Authorization", "Bearer %s" % token)

        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = json.loads(response.read().decode("utf-8"))
                link = response.headers.get("Link", "")
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", "replace")
            raise SystemExit(
                "GitHub API request failed with HTTP %d: %s" % (error.code, body)
            )

        if not payload:
            break

        for entry in payload:
            starred_at = entry.get("starred_at")
            if not starred_at:
                continue
            dates.append(
                datetime.strptime(starred_at, "%Y-%m-%dT%H:%M:%SZ").date()
            )

        url = _next_page_url(link)
        if not url:
            break

    if not dates:
        raise SystemExit("No stargazers returned for %s" % repo)

    return sorted(dates)


def _next_page_url(link_header):
    for part in link_header.split(","):
        match = re.search(r'<([^>]+)>;\s*rel="next"', part)
        if match:
            return match.group(1)
    return None


def cumulative_series(dates):
    """Collapse star timestamps into one cumulative point per day with stars."""
    counts = {}
    for starred_on in dates:
        counts[starred_on] = counts.get(starred_on, 0) + 1

    series = []
    total = 0
    for starred_on in sorted(counts):
        total += counts[starred_on]
        series.append((starred_on, total))
    return series


def nice_step(raw_step):
    """Round a raw axis step up to a 1/2/2.5/5 * 10^n value."""
    if raw_step <= 0:
        return 1
    magnitude = 10 ** int(_floor_log10(raw_step))
    for factor in (1, 2, 2.5, 5, 10):
        if raw_step <= factor * magnitude:
            return max(1, int(factor * magnitude))
    return max(1, int(10 * magnitude))


def _floor_log10(value):
    exponent = 0
    while value >= 10:
        value /= 10.0
        exponent += 1
    while value < 1:
        value *= 10.0
        exponent -= 1
    return exponent


def month_ticks(first_day, last_day, wanted):
    """Pick up to `wanted` evenly spaced ticks snapped to month starts."""
    span = (last_day - first_day).days
    if span <= 0:
        return [first_day]

    ticks = []
    for index in range(wanted):
        offset = span * index / float(wanted - 1)
        candidate = first_day + timedelta(days=offset)
        ticks.append(candidate.replace(day=1))

    deduped = []
    for tick in ticks:
        if tick < first_day:
            tick = first_day
        if not deduped or tick != deduped[-1]:
            deduped.append(tick)
    return deduped


def format_count(value):
    return "{:,}".format(int(value))


def escape(text):
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def render_svg(series, repo):
    plot_width = WIDTH - MARGIN_LEFT - MARGIN_RIGHT
    plot_height = HEIGHT - MARGIN_TOP - MARGIN_BOTTOM
    baseline = MARGIN_TOP + plot_height

    first_day, _ = series[0]
    last_day, total = series[-1]
    span_days = max((last_day - first_day).days, 1)

    step = nice_step(total / 5.0)
    y_max = step * ((total + step - 1) // step)
    y_max = max(y_max, step)

    def x_for(day):
        return MARGIN_LEFT + (day - first_day).days / float(span_days) * plot_width

    def y_for(count):
        return baseline - (count / float(y_max)) * plot_height

    points = " ".join(
        "%.1f,%.1f" % (x_for(day), y_for(count)) for day, count in series
    )
    area_path = "M %.1f,%.1f L %s L %.1f,%.1f Z" % (
        x_for(first_day),
        baseline,
        points.replace(" ", " L "),
        x_for(last_day),
        baseline,
    )

    parts = []
    parts.append(
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
        'viewBox="0 0 %d %d" role="img" '
        'aria-label="Stargazers over time for %s">'
        % (WIDTH, HEIGHT, WIDTH, HEIGHT, escape(repo))
    )
    parts.append("<title>Stargazers over time</title>")
    parts.append(
        "<desc>%s has %s stargazers as of %s.</desc>"
        % (escape(repo), format_count(total), last_day.isoformat())
    )
    parts.append(
        "<defs><linearGradient id=\"area\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">"
        '<stop offset="0%%" stop-color="%s" stop-opacity="0.28"/>'
        '<stop offset="100%%" stop-color="%s" stop-opacity="0.02"/>'
        "</linearGradient></defs>"
        % (LINE_COLOR, LINE_COLOR)
    )
    parts.append(
        '<rect width="%d" height="%d" fill="%s"/>' % (WIDTH, HEIGHT, BACKGROUND_COLOR)
    )

    # Title and total.
    parts.append(
        '<text x="%d" y="28" font-family="Segoe UI, Helvetica, Arial, sans-serif" '
        'font-size="17" font-weight="600" fill="%s">Stargazers over time</text>'
        % (MARGIN_LEFT, TITLE_COLOR)
    )
    parts.append(
        '<text x="%d" y="28" font-family="Segoe UI, Helvetica, Arial, sans-serif" '
        'font-size="13" fill="%s" text-anchor="end">%s &#183; %s stars</text>'
        % (WIDTH - MARGIN_RIGHT + 88, TEXT_COLOR, escape(repo), format_count(total))
    )

    # Horizontal grid lines and y axis labels.
    y_value = 0
    while y_value <= y_max:
        y = y_for(y_value)
        parts.append(
            '<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s" '
            'stroke-width="1" stroke-opacity="0.55"/>'
            % (MARGIN_LEFT, y, MARGIN_LEFT + plot_width, y, AXIS_COLOR)
        )
        parts.append(
            '<text x="%d" y="%.1f" font-family="Segoe UI, Helvetica, Arial, sans-serif" '
            'font-size="11" fill="%s" text-anchor="end">%s</text>'
            % (MARGIN_LEFT - 10, y + 4, TEXT_COLOR, format_count(y_value))
        )
        y_value += step

    # X axis labels.
    for tick in month_ticks(first_day, last_day, 6):
        x = x_for(tick)
        parts.append(
            '<text x="%.1f" y="%d" font-family="Segoe UI, Helvetica, Arial, sans-serif" '
            'font-size="11" fill="%s" text-anchor="middle">%s</text>'
            % (x, baseline + 20, TEXT_COLOR, tick.strftime("%b %Y"))
        )

    # Axis lines.
    parts.append(
        '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1"/>'
        % (MARGIN_LEFT, baseline, MARGIN_LEFT + plot_width, baseline, AXIS_COLOR)
    )
    parts.append(
        '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1"/>'
        % (MARGIN_LEFT, MARGIN_TOP, MARGIN_LEFT, baseline, AXIS_COLOR)
    )

    # Area and line.
    parts.append('<path d="%s" fill="url(#area)"/>' % area_path)
    parts.append(
        '<polyline points="%s" fill="none" stroke="%s" stroke-width="2" '
        'stroke-linejoin="round" stroke-linecap="round"/>'
        % (points, LINE_COLOR)
    )

    # Last point marker and value.
    last_x, last_y = x_for(last_day), y_for(total)
    parts.append(
        '<circle cx="%.1f" cy="%.1f" r="3.5" fill="%s"/>'
        % (last_x, last_y, LINE_COLOR)
    )
    parts.append(
        '<text x="%.1f" y="%.1f" font-family="Segoe UI, Helvetica, Arial, sans-serif" '
        'font-size="12" font-weight="600" fill="%s">%s</text>'
        % (last_x + 8, last_y + 4, TITLE_COLOR, format_count(total))
    )

    # Footnote.
    parts.append(
        '<text x="%d" y="%d" font-family="Segoe UI, Helvetica, Arial, sans-serif" '
        'font-size="10" fill="%s" text-anchor="end">Data through %s</text>'
        % (WIDTH - 8, HEIGHT - 8, TEXT_COLOR, last_day.isoformat())
    )

    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--output", default="assets/star-history.svg")
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN"))
    args = parser.parse_args()

    if not args.repo:
        raise SystemExit("--repo (or GITHUB_REPOSITORY) is required")

    star_dates = fetch_star_dates(args.repo, args.token)
    series = cumulative_series(star_dates)
    svg = render_svg(series, args.repo)

    output_dir = os.path.dirname(args.output)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    with open(args.output, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(svg)

    print(
        "Wrote %s: %s stars across %d active days (%s to %s)"
        % (
            args.output,
            format_count(series[-1][1]),
            len(series),
            series[0][0].isoformat(),
            series[-1][0].isoformat(),
        )
    )


if __name__ == "__main__":
    sys.exit(main())
