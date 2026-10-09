# Code-side guard on AI output (not trusted to the model): the source check never names a person who is not in the
# reporter's own notes or sources.
#
# Production UnityUpdates' rule (NO_SUBJECT): "You never invent a person's name ... a person appears only as someone to
# call." The demo enforces the first half in code. It pulls likely person names out of the output and fails it when
# one of them appears nowhere in what the reporter typed (headline, beat, notes, sources). Same heuristics as
# open-votepip's PersonNameCheck, which runs the opposite way (there, a name from the input must not come back):
#
#   - a title followed by a capitalized word ("Councillor Brannigan", "Ms. Okafor", "Treasurer Calloway");
#   - two or three capitalized words in a row ("Ines Calloway") with no place or organization word ("Fenwick Street",
#     "Water District") and no common capitalized word (days, months, question words, "Request", "The", ...).
#
# A name passes when its surname (the last word) or the full name appears anywhere in the input, ignoring case, or
# when its surname is also used as an ordinary lowercase word ("Harbor Minutes" when the text says "minutes"). A first
# name on its own is not detected. It is a heuristic that errs toward blocking; a blocked check shows the reporter a
# plain reason and a Retry button.
class PersonNameCheck
  Name = Struct.new(:full, :surname, keyword_init: true)

  TITLES = %w[
    Mr Mrs Ms Mx Miss Dr Rev Reverend Pastor Father Sister Brother Elder Deacon Rabbi Imam Bishop Cantor
    Councillor Councilor Councilman Councilwoman Alderman Alderwoman Mayor Coach Professor Prof Treasurer Chair
    Chairperson Secretary President Director Captain Officer Judge Senator Trustee Commissioner Superintendent
    Principal Sheriff Chief Inspector Auntie Uncle
  ].freeze

  STOPWORDS = %w[
    The A An And Or But Nor Of In On At For To By From With Without Into Onto Over Under After Before During
    Until Since As If When While Where Why How What Which Who Whom Whose That This These Those There Here
    Our Your Their My His Her Its We You They I He She It Us Them Every Each All Any Some No Not Yes Please
    Thank Thanks Also Then So Let Lets Members Member Everyone Everybody Nobody Anyone None
    Is Are Was Were Do Does Did Has Have Had Can Could Would Should Will Shall May Might Must
    Ask Request Get Confirm Check Find Call Obtain Compare Read Look Attend Contact Interview Verify Pull See
    Name Quote Add Cite Mark Talk Speak Follow Note Source Sources Claim Claims
    Reported Announcement Opinion Explainer Sourced Unsourced Single
    Monday Tuesday Wednesday Thursday Friday Saturday Sunday
    January February March April May June July August September October November December
    Christmas Easter Thanksgiving Ramadan Passover Diwali Hanukkah
  ].freeze

  ORG_WORDS = %w[
    Street St Road Rd Avenue Ave Lane Drive Way Boulevard Blvd Place Square Park Garden Gardens Hall Room Rooms
    Center Centre Library School Church Chapel Temple Mosque Synagogue Meeting House Housing Co-op Coop
    Cooperative Association Society Club Committee Council Board Fund Trust Foundation Union League Network
    Group Team Commons Community Neighborhood Neighbourhood Village Town City County State Market Fair Festival
    Day Night Week Month Year Annual Kitchen Pantry Bank Shop Store Cafe Building Tower Court Commission Assembly
    Circle Collective Project Program Programme Plan Policy Rule Rules Bylaws Bylaw Section Article Act Agreement
    Lake River Creek Hill Hills Valley Woods Forest Bridge Station North South East West Upper Lower New Old
    Saint Mount Tool Tools Lobby Office Department Ministry Mission Shelter Clinic Hospital Farm Orchard Field
    Fields Playground Pool Gym Studio Theater Theatre Museum Gallery Reserve Budget Account Hub Lab Works
    District Authority Agency Utility Utilities Water Sewer Transit Police Fire Services Service Elementary Middle
    High Academy University College Parish Diocese Congregation Ward Wing Annex Apartments Tenants Residents
    Minutes Records Report Agenda Notice Letter Newsletter Bulletin Gazette Times Herald Ledger News Press Radio
    Company Inc Corp Corporation Partners Holdings Operations Finance Payroll Facilities Maintenance
  ].freeze

  WORD = /[A-Z][a-zA-Z]*[a-z](?:['’-][A-Za-z]+)*/
  RUN  = /(?<![[:alnum:]])#{WORD}(?:[ \t]+#{WORD})*(?![[:alnum:]])/
  ABBREVIATED_TITLE = /\b(Mr|Mrs|Ms|Mx|Dr|Rev|Prof|St)\./

  # Likely person names in `output` that appear nowhere in `input`, as strings (empty when the output is clean).
  def self.invented_in(output, input)
    input = input.to_s
    plain = ordinary_words(input + "\n" + output.to_s)
    names_in(output, plain: plain).filter_map do |name|
      next if plain.include?(name.surname.downcase)
      next if [ name.surname, name.full ].compact.any? { |part| input.match?(bounded(part)) }
      name.full || name.surname
    end.uniq
  end

  def self.clean?(output, input)
    invented_in(output, input).empty?
  end

  # Likely person names in a block of text. `plain` is the set of words the text uses in lowercase.
  def self.names_in(text, plain: ordinary_words(text))
    text  = text.to_s.gsub(ABBREVIATED_TITLE, '\1')
    names = []

    text.each_line do |line|
      next if headline?(line)

      line.scan(RUN).each do |run|
        words = run.split(/[ \t]+/)
        names.concat(names_from_titles(words))
        names.concat(names_from_run(words.reject { |w| TITLES.include?(w) }, plain))
      end
    end
    names.uniq
  end

  # A title-cased heading ("Garden Lot Sale Vote Moved To June") reads as a run of capitals but is not a name.
  def self.headline?(line)
    words = line.scan(/[A-Za-z][\w'’-]*/)
    return false if words.size < 4
    capitalized = words.count { |w| w.match?(/\A[A-Z]/) }
    capitalized.to_f / words.size >= 0.75
  end

  # "Councillor Brannigan", "Pastor Ruth Abernathy": the words after a title, up to a stopword.
  def self.names_from_titles(words)
    words.each_index.filter_map do |i|
      next unless TITLES.include?(words[i])
      following = words[(i + 1)..].take_while { |w| name_word?(w) }.first(3)
      next if following.empty?
      Name.new(full: following.size >= 2 ? following.join(" ") : nil, surname: following.last)
    end
  end

  # "Ines Calloway": 2-3 name-like words in a row. A leading word the text also uses in lowercase ("Phone",
  # "Visit") is an ordinary word at the start of a sentence, not part of a name.
  def self.names_from_run(words, plain)
    return [] if words.any? { |w| ORG_WORDS.include?(w) }

    words.slice_when { |a, b| !name_word?(a) || !name_word?(b) }
         .map { |seg| seg.select { |w| name_word?(w) } }
         .map { |seg| seg.drop_while { |w| plain.include?(w.downcase) } }
         .select { |seg| seg.size.between?(2, 3) }
         .map { |seg| Name.new(full: seg.join(" "), surname: seg.last) }
  end

  def self.name_word?(word)
    !STOPWORDS.include?(word) && !ORG_WORDS.include?(word) && !TITLES.include?(word)
  end

  def self.ordinary_words(text)
    text.to_s.scan(/(?<![[:alnum:]])[a-z][a-z'’-]+/).to_set
  end

  def self.bounded(phrase)
    Regexp.new("(?<![[:alnum:]])#{Regexp.escape(phrase)}(?![[:alnum:]])", Regexp::IGNORECASE)
  end

  private_class_method :headline?, :names_from_titles, :names_from_run, :name_word?, :ordinary_words, :bounded
end
