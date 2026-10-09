# Code-side guard on AI output (not trusted to the model): the source check never invents a source.
#
# Production UnityUpdates' source_check_assist names "the source exactly as listed, or none", and the app attaches
# the claim to that source record. The demo has no source records, only the reporter's own Sources box, so this
# check reads the names the model gave for each sourced or single_source claim and fails the output when one of
# them is not in that box.
#
# A claim backed by two sources may name both, separated by ";" (the prompt asks for "; "). Each name must appear
# in the sources text on word boundaries, ignoring case, runs of whitespace and curly quotes, so "Board minutes"
# matches "board minutes, March 12 meeting (document)". Models often decorate a listed name, so a name also passes
# when it matches with its parentheses removed ("Board minutes (March 12)") or when the part before its first comma
# matches ("Ines Calloway, the treasurer"). A name shorter than three characters never matches: "a" or "Jo" is not
# evidence of anything.
class SourceNameCheck
  MIN_LENGTH = 3
  NONE       = /\A\s*(none|n\/a|no source)?\s*\z/i

  # Names given for sourced or single_source claims that do not appear in the sources text, as strings.
  def self.unlisted(claims, sources_text)
    haystack = normalize(sources_text)
    Array(claims).flat_map do |claim|
      next [] unless %w[sourced single_source].include?(claim["state"])
      names(claim["source_name"]).reject { |name| listed?(name, haystack) }
    end.uniq
  end

  # "Board minutes; Ines Calloway" => ["Board minutes", "Ines Calloway"]
  def self.names(source_name)
    source_name.to_s.split(";").map(&:strip).reject(&:empty?)
  end

  # True for "", "none", "None", "n/a": what an unsourced claim should carry.
  def self.none?(source_name)
    source_name.to_s.match?(NONE)
  end

  def self.listed?(name, haystack)
    bare = name.gsub(/\([^)]*\)/, " ")
    [ name, bare, bare.split(",").first ].map { |n| normalize(n).sub(/[.,;:]+\z/, "") }.uniq.any? do |needle|
      needle.length >= MIN_LENGTH && haystack.match?(/(?<![[:alnum:]])#{Regexp.escape(needle)}(?![[:alnum:]])/)
    end
  end

  def self.normalize(text)
    text.to_s.downcase.tr("‘’“”", "''\"\"").gsub(/\s+/, " ").strip
  end

  private_class_method :listed?, :normalize
end
