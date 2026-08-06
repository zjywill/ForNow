#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "set"

ROOT = File.expand_path("..", __dir__)
LEDGER_PATH = File.join(ROOT, "docs", "00_SOURCE_LEDGER.md")
SPEC_PATH = File.join(ROOT, "docs", "01_PRODUCT_SPEC.md")
MATRIX_PATH = File.join(ROOT, "docs", "04_TEST_MATRIX.md")
WALKTHROUGH_PATH = File.join(ROOT, "docs", "06_MANUAL_WALKTHROUGH.md")
OUTPUT_PATH = File.join(ROOT, "docs", "traceability.yml")

TEST_ID = /(?:UT|IT|ET|UIT|MT|PT|ST|SOAK|FAULT)-[A-Z0-9]+-\d{3}[A-Z]?/

def heading_blocks(text, pattern)
  matches = []
  text.to_enum(:scan, pattern).each do
    match = Regexp.last_match
    matches << [match[1], match[2], match.begin(0), match.end(0)]
  end

  matches.each_with_index.to_h do |(id, title, _start_offset, body_offset), index|
    next_offset = matches[index + 1]&.at(2) || text.length
    [id, { "title" => title.strip, "body" => text[body_offset...next_offset] }]
  end
end

def expand_test_range(first, last)
  first_letter = first.match(/\A(.+-\d{3})([A-Z])\z/)
  last_letter = last.match(/\A(.+-\d{3})([A-Z])\z/)
  if first_letter && last_letter && first_letter[1] == last_letter[1]
    return (first_letter[2]..last_letter[2]).map { |suffix| "#{first_letter[1]}#{suffix}" }
  end

  first_number = first.match(/\A(.+-)(\d{3})\z/)
  last_number = last.match(/\A(.+-)(\d{3})\z/)
  if first_number && last_number && first_number[1] == last_number[1]
    return (first_number[2].to_i..last_number[2].to_i).map do |number|
      format("%s%03d", first_number[1], number)
    end
  end

  raise "Unsupported test range: #{first} through #{last}"
end

def expanded_test_ids(text)
  ids = text.scan(/`(#{TEST_ID})`/).flatten.to_set
  text.scan(/`(#{TEST_ID})`\s+through\s+`(#{TEST_ID})`/).each do |first, last|
    expand_test_range(first, last).each { |id| ids << id }
  end
  ids.to_a.sort
end

def fallback_source_urls(description)
  normalized = description.downcase
  urls = []
  urls << "https://antinote.io/user-manual" if normalized.include?("manual")
  if normalized.include?("product") || normalized.include?("faq")
    urls << "https://antinote.io/"
  end
  urls << "https://antinote.io/changelog" if normalized.include?("changelog")
  urls << "https://antinote.io/presskit" if normalized.include?("press kit")
  if normalized.include?("extension")
    urls << "https://antinote.io/extensions"
  end
  if normalized.include?("repository")
    urls << "https://github.com/johnsonfung/antinote-extensions"
  end
  if normalized.include?("digital trends") || normalized.include?("press review")
    urls << "https://www.digitaltrends.com/computing/this-mac-app-is-the-perfect-way-to-capture-your-ideas-and-stay-organized/"
  end
  urls << "https://antinote.io/" if urls.empty?
  urls.uniq.sort
end

def manual_urls_by_requirement(text)
  matches = []
  text.to_enum(:scan, /^Source: (https:\/\/\S+)$/).each do
    match = Regexp.last_match
    matches << [match[1], match.end(0), match.begin(0)]
  end

  mapping = Hash.new { |hash, key| hash[key] = Set.new }
  matches.each_with_index do |(url, body_offset, _start_offset), index|
    next_offset = matches[index + 1]&.at(2) || text.length
    block = text[body_offset...next_offset]
    block.scan(/`(FR-[A-Z0-9-]+-\d{3})`/).flatten.each do |requirement_id|
      mapping[requirement_id] << url
    end
  end
  mapping.transform_values { |urls| urls.to_a.sort }
end

ledger = File.read(LEDGER_PATH)
spec = File.read(SPEC_PATH)
matrix = File.read(MATRIX_PATH)
walkthrough = File.read(WALKTHROUGH_PATH)

evidence_blocks = heading_blocks(
  ledger,
  /^### (AN-[A-Z0-9-]+-\d{3}) - (.+)$/
)
requirement_blocks = heading_blocks(
  spec,
  /^#### (FR-[A-Z0-9-]+-\d{3}) - (.+)$/
)
manual_urls = manual_urls_by_requirement(walkthrough)

matrix_tests = {}
matrix.each_line do |line|
  match = line.match(/^\| `(FR-[A-Z0-9-]+-\d{3})` \| (.+?) \|/)
  next unless match

  matrix_tests[match[1]] = expanded_test_ids(match[2])
end

missing_rows = requirement_blocks.keys.to_set - matrix_tests.keys.to_set
raise "Requirements missing test rows: #{missing_rows.to_a.sort.join(', ')}" unless missing_rows.empty?

requirements = requirement_blocks.to_h do |id, block|
  source_line = block.fetch("body").each_line.find { |line| line.start_with?("- Source: ") }
  raise "#{id} has no source line" unless source_line

  source_description = source_line.delete_prefix("- Source: ").strip
  evidence_ids = source_description.scan(/`(AN-[A-Z0-9-]+-\d{3})`/).flatten.sort
  decision_ids = source_description.scan(/`(FORNOW-DECISION-\d{3})`/).flatten.sort
  classification = if source_description.start_with?("product-quality")
                     "quality"
                   elsif decision_ids.empty?
                     "parity"
                   else
                     "product-decision"
                   end
  release = if block.fetch("body").include?("- Target: `1.x`.")
              "post-1.0"
            else
              "macos-1.0"
            end

  [
    id,
    {
      "title" => block.fetch("title"),
      "classification" => classification,
      "sourceDescription" => source_description,
      "evidence" => evidence_ids,
      "decisions" => decision_ids,
      "release" => release,
      "tests" => matrix_tests.fetch(id),
      "manualURLs" => manual_urls.fetch(id, []),
    },
  ]
end

evidence = evidence_blocks.to_h do |id, block|
  level = block.fetch("body")[/^- Level: `([^`]+)`$/, 1]
  source_description = block.fetch("body")[/^- Source: (.+)$/, 1]
  raise "#{id} has no evidence level" unless level
  raise "#{id} has no source description" unless source_description

  applicable_requirements = requirements.each_with_object([]) do |(requirement_id, entry), ids|
    ids << requirement_id if entry.fetch("evidence").include?(id)
  end.sort
  urls = fallback_source_urls(source_description)
  applicable_requirements.each do |requirement_id|
    urls.concat(manual_urls.fetch(requirement_id, []))
  end

  [
    id,
    {
      "title" => block.fetch("title"),
      "confidence" => level,
      "sourceDescription" => source_description,
      "sourceURLs" => urls.uniq.sort,
      "requirements" => applicable_requirements,
    },
  ]
end

traceability = {
  "version" => 1,
  "scope" => "fornow-macos",
  "reviewed" => "2026-08-03",
  "undocumentedMarker" => "UNVERIFIED",
  "evidence" => evidence,
  "requirements" => requirements,
}
generated = "#{JSON.pretty_generate(traceability)}\n"

if ARGV == ["--check"]
  unless File.file?(OUTPUT_PATH) && File.read(OUTPUT_PATH) == generated
    warn "docs/traceability.yml is not current; run scripts/generate-traceability.rb"
    exit 1
  end
  puts "traceability generation check: PASS"
  exit 0
end

raise "Usage: #{File.basename($PROGRAM_NAME)} [--check]" unless ARGV.empty?

File.write(OUTPUT_PATH, generated)
puts "wrote #{OUTPUT_PATH}"
puts "evidence: #{evidence.size}"
puts "requirements: #{requirements.size}"
puts "mapped test IDs: #{requirements.sum { |_id, entry| entry.fetch('tests').size }}"
