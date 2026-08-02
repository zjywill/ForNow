#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"
require "yaml"

ROOT = File.expand_path("..", __dir__)
IOS_DIR = File.join(ROOT, "docs", "ios")

requirements_path = File.join(IOS_DIR, "02_IOS_REQUIREMENTS.md")
matrix_path = File.join(IOS_DIR, "04_IOS_TEST_MATRIX.md")
trace_path = File.join(IOS_DIR, "traceability.yml")
ledger_path = File.join(ROOT, "docs", "00_SOURCE_LEDGER.md")

requirements_text = File.read(requirements_path)
matrix_text = File.read(matrix_path)
ledger_text = File.read(ledger_path)
ios_text = Dir[File.join(IOS_DIR, "*.{md,yml}")].sort.map { |path| File.read(path) }.join("\n")
trace = YAML.safe_load(File.read(trace_path), permitted_classes: [], aliases: false)

errors = []

defined_requirements = requirements_text
  .scan(/^### (FR-IOS-[A-Z0-9]+-\d{3})\b/)
  .flatten
  .to_set
traced_requirements = trace.fetch("requirements").keys.to_set

(defined_requirements - traced_requirements).sort.each do |id|
  errors << "#{id} is defined but missing from traceability.yml"
end
(traced_requirements - defined_requirements).sort.each do |id|
  errors << "#{id} is traced but not defined in 02_IOS_REQUIREMENTS.md"
end

matrix_requirements = matrix_text.scan(/`(FR-IOS-[A-Z0-9]+-\d{3})`/).flatten.to_set
(matrix_requirements - traced_requirements).sort.each do |id|
  errors << "#{id} appears in the test matrix but is not traced"
end
(traced_requirements - matrix_requirements).sort.each do |id|
  errors << "#{id} is traced but has no test-matrix row"
end

test_id_pattern = /(?:UT|ET|IT|UIT|MT|PT|ST|SP)-IOS-[A-Z0-9]+-\d{3}[A-Z]?/
matrix_tests = matrix_text.scan(test_id_pattern).to_set

matrix_text.scan(
  /`((?:UT|ET|IT|UIT|MT|PT|ST|SP)-IOS-[A-Z0-9]+-\d{3})([A-Z])`\s+through\s+`\1([A-Z])`/
).each do |prefix, first_suffix, last_suffix|
  (first_suffix..last_suffix).each { |suffix| matrix_tests << "#{prefix}#{suffix}" }
end

trace.fetch("requirements").each do |id, entry|
  decisions = entry.fetch("decisions")
  tests = entry.fetch("tests")
  errors << "#{id} has no controlling product decision" if decisions.empty?
  errors << "#{id} has no tests" if tests.empty?
  tests.each do |test_id|
    errors << "#{id} references missing test #{test_id}" unless matrix_tests.include?(test_id)
  end

  source_path, source_anchor = entry.fetch("source").split("#", 2)
  absolute_source_path = File.join(IOS_DIR, source_path)
  unless File.file?(absolute_source_path)
    errors << "#{id} references missing source file #{source_path}"
    next
  end

  next unless source_anchor

  source_slugs = File.read(absolute_source_path)
    .scan(/^\#{1,6}\s+(.+)$/)
    .flatten
    .map do |heading|
      heading
        .downcase
        .gsub(/[`*_]/, "")
        .gsub(/[^a-z0-9\s-]/, "")
        .strip
        .gsub(/\s+/, "-")
        .gsub(/-+/, "-")
    end
    .to_set
  errors << "#{id} references missing source anchor ##{source_anchor}" unless source_slugs.include?(source_anchor)
end

defined_decisions = ledger_text
  .scan(/^### (FORNOW-DECISION-\d{3})\b/)
  .flatten
  .to_set
referenced_decisions = ios_text.scan(/FORNOW-DECISION-\d{3}/).to_set
(referenced_decisions - defined_decisions).sort.each do |id|
  errors << "#{id} is referenced by iOS docs but not defined in the source ledger"
end

forbidden_phrases = {
  "same transaction as the database mutation" => "Core Spotlight cannot share a SQLite transaction",
  "same commit boundary" => "external indexing cannot share the SQLite commit boundary",
  "shared App Group keychain" => "Keychain Access Groups and App Groups are separate",
  "full macOS shortcut set" => "iOS requires an explicit applicable shortcut table",
  "critical-banner" => "iOS 1.0 does not require Critical Alerts"
}

forbidden_phrases.each do |phrase, reason|
  errors << "forbidden phrase '#{phrase}': #{reason}" if ios_text.include?(phrase)
end

release_requirements = trace.fetch("requirements").count do |_id, entry|
  entry.fetch("release") == "ios-1.0"
end

if errors.empty?
  puts "iOS documentation validation: PASS"
  puts "requirements: #{defined_requirements.size}/#{traced_requirements.size}"
  puts "release requirements: #{release_requirements}"
  puts "mapped test IDs: #{trace.fetch("requirements").sum { |_id, entry| entry.fetch("tests").size }}"
  puts "defined decisions: #{defined_decisions.size}"
  exit 0
end

warn "iOS documentation validation: FAIL"
errors.each { |error| warn "- #{error}" }
exit 1
