#!/usr/bin/env python3
"""brave-to-sql.py

Convert Brave Search JSONL results (from brave-search-carvana.sh) into
a PostgreSQL seed file for the CarScope vehicles + price_snapshots tables.

Usage:
    python3 brave-to-sql.py <carvana_results.jsonl> [--output seed-file.sql]

It parses Carvana URLs, titles, and descriptions to extract:
  - make, model, year, trim
  - price (in cents)
  - mileage
  - real Carvana URL

Output is a SQL file wrapped in BEGIN/COMMIT with:
  - INSERT INTO vehicles ... ON CONFLICT DO NOTHING
  - INSERT INTO price_snapshots ... referencing vehicles by subquery
"""

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


@dataclass
class Listing:
    make: str
    model: str
    year: int
    trim: Optional[str]
    price_cents: int
    mileage: int
    url: str
    source: str = "carvana"

    @property
    def vehicle_key(self):
        return (self.make, self.model, self.year, self.trim)


def parse_price(text: str) -> Optional[int]:
    """Extract first dollar price from text, return cents."""
    m = re.search(r'\$([0-9,]+)', text)
    if m:
        val = int(m.group(1).replace(',', ''))
        return val * 100
    return None


def parse_mileage(text: str) -> Optional[int]:
    """Extract mileage from text like '45,993 miles' or '45k miles'."""
    # Try exact format: "45,993 miles"
    m = re.search(r'([\d,]+)\s*miles?', text, re.IGNORECASE)
    if m:
        val = m.group(1).replace(',', '')
        return int(val)
    # Try "45k miles"
    m = re.search(r'(\d+)k\s*miles?', text, re.IGNORECASE)
    if m:
        return int(m.group(1)) * 1000
    return None


def parse_year(text: str) -> Optional[int]:
    """Extract 4-digit year from text."""
    m = re.search(r'(20[12]\d)', text)
    if m:
        return int(m.group(1))
    return None


# Known make/model patterns
KNOWN_VEHICLES = {
    'rav4': ('Toyota', 'RAV4'),
    'rav4 hybrid': ('Toyota', 'RAV4 Hybrid'),
    'rav4 prime': ('Toyota', 'RAV4 Prime'),
    'macan': ('Porsche', 'Macan'),
    'rdx': ('Acura', 'RDX'),
    'cr-v': ('Honda', 'CR-V'),
    'crv': ('Honda', 'CR-V'),
    'cx-5': ('Mazda', 'CX-5'),
    'cx5': ('Mazda', 'CX-5'),
    'tucson': ('Hyundai', 'Tucson'),
    'forester': ('Subaru', 'Forester'),
    'outback': ('Subaru', 'Outback'),
    'equinox': ('Chevrolet', 'Equinox'),
    'trailblazer': ('Chevrolet', 'Trailblazer'),
    'escape': ('Ford', 'Escape'),
    'edge': ('Ford', 'Edge'),
    'explorer': ('Ford', 'Explorer'),
    'rogue': ('Nissan', 'Rogue'),
    'atlas': ('Volkswagen', 'Atlas'),
    'compass': ('Jeep', 'Compass'),
    'renegade': ('Jeep', 'Renegade'),
    '4runner': ('Toyota', '4Runner'),
    'sequoia': ('Toyota', 'Sequoia'),
    'venue': ('Hyundai', 'Venue'),
    'encore': ('Buick', 'Encore'),
    'hr-v': ('Honda', 'HR-V'),
    'sorento': ('Kia', 'Sorento'),
    'sportage': ('Kia', 'Sportage'),
}

KNOWN_TRIMS = [
    'XLE Premium', 'XLE', 'XSE', 'LE', 'SE', 'Limited', 'Premium',
    'XLT', 'LT', 'LS', 'LX', 'EX', 'EX-L',
    'SH-AWD w/Advance Pkg', 'SH-AWD w/Technology Pkg', 'SH-AWD w/A-SPEC Pkg',
    'FWD w/Technology Pkg', 'FWD w/A-SPEC Pkg', 'FWD w/A-Spec Pkg',
    'A-SPEC Pkg', 'Technology Pkg', 'Advance Pkg',
    'Turbo', 'GTS', 'S', 'base',
    'Sport', 'Preferred', 'Essence',
    'ACTIV', 'Latitude', 'SEL', 'SR', 'SV',
]


def parse_make_model(text: str):
    """Try to extract make and model from title/URL text."""
    text_lower = text.lower()
    for key, (make, model) in KNOWN_VEHICLES.items():
        if key in text_lower:
            return make, model
    return None, None


def parse_trim(text: str) -> Optional[str]:
    """Extract trim level from title/description."""
    for trim in KNOWN_TRIMS:
        if trim in text:
            return trim
    return None


def parse_vehicle_listing(title: str, desc: str, url: str) -> Optional[Listing]:
    """Attempt to parse a single Carvana search result into a Listing."""
    combined = f"{title} {desc}"

    make, model = parse_make_model(combined)
    if not make:
        return None

    year = parse_year(title) or parse_year(url)
    if not year or year < 2018 or year > 2023:
        return None

    price_cents = parse_price(desc)
    if not price_cents:
        return None

    mileage = parse_mileage(desc)
    if not mileage:
        return None

    trim = parse_trim(combined)

    return Listing(
        make=make,
        model=model,
        year=year,
        trim=trim,
        price_cents=price_cents,
        mileage=mileage,
        url=url,
    )


def sql_val(s: Optional[str]) -> str:
    """Escape a string for SQL or return NULL."""
    if s is None:
        return "NULL"
    escaped = s.replace("'", "''")
    return f"'{escaped}'"


def generate_sql(listings: list[Listing]) -> str:
    """Generate the full SQL seed file."""
    lines = []
    lines.append("-- seed-suvs.sql")
    lines.append("-- SUV seed data extracted from Carvana via Brave Search API (Feb 2026)")
    lines.append("-- Generated by brave-to-sql.py")
    lines.append("")
    lines.append("BEGIN;")
    lines.append("")
    lines.append("-- ============================================================")
    lines.append("-- 1. INSERT vehicles with ON CONFLICT DO NOTHING")
    lines.append("-- ============================================================")
    lines.append("")

    # Deduplicate vehicles
    seen_vehicles = set()
    for l in listings:
        key = l.vehicle_key
        if key in seen_vehicles:
            continue
        seen_vehicles.add(key)
        lines.append(
            f"INSERT INTO vehicles (make, model, year, trim) "
            f"VALUES ({sql_val(l.make)}, {sql_val(l.model)}, {l.year}, {sql_val(l.trim)}) "
            f"ON CONFLICT DO NOTHING;"
        )

    lines.append("")
    lines.append("-- ============================================================")
    lines.append("-- 2. INSERT price_snapshots referencing those vehicles")
    lines.append("--    Prices are in cents. Data from Carvana via Brave Search API.")
    lines.append("-- ============================================================")
    lines.append("")

    for l in listings:
        trim_where = f"trim={sql_val(l.trim)}" if l.trim else "trim IS NULL"
        comment = (
            f"-- {l.make} {l.model} {l.year} {l.trim or 'base'} "
            f"- {l.mileage:,} mi - ${l.price_cents // 100:,}"
        )
        lines.append(comment)
        lines.append(
            f"INSERT INTO price_snapshots (time, vehicle_id, price_cents, mileage, source, location, url)\n"
            f"VALUES (NOW(), "
            f"(SELECT id FROM vehicles WHERE make={sql_val(l.make)} AND model={sql_val(l.model)} "
            f"AND year={l.year} AND {trim_where} LIMIT 1),\n"
            f"  {l.price_cents}, {l.mileage}, 'carvana', NULL, {sql_val(l.url)});"
        )
        lines.append("")

    lines.append("COMMIT;")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Convert Brave search JSONL to SQL seed file")
    parser.add_argument("input", nargs="?", help="JSONL file from brave-search-carvana.sh")
    parser.add_argument("--output", "-o", default=None, help="Output SQL file path")
    args = parser.parse_args()

    # Read from file or stdin
    if args.input:
        with open(args.input) as f:
            raw_lines = f.readlines()
    else:
        raw_lines = sys.stdin.readlines()

    listings = []
    seen = set()  # dedupe by (url, price, mileage)

    for line in raw_lines:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue

        listing = parse_vehicle_listing(
            rec.get('title', ''),
            rec.get('description', ''),
            rec.get('url', ''),
        )
        if listing:
            dedup_key = (listing.url, listing.price_cents, listing.mileage)
            if dedup_key not in seen:
                seen.add(dedup_key)
                listings.append(listing)

    if not listings:
        print("No valid listings found in input.", file=sys.stderr)
        sys.exit(1)

    sql = generate_sql(listings)

    if args.output:
        Path(args.output).write_text(sql)
        print(f"Wrote {len(listings)} listings to {args.output}", file=sys.stderr)
    else:
        print(sql)


if __name__ == "__main__":
    main()
