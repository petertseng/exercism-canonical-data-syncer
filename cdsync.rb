require 'json'

TestCase = Struct.new(:uuid, :comments_above, :included)

TEST_CASE = %r{"?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"?\s*=\s*(true|false)}

def bool(s)
  case s
  when 'true'
    true
  when 'false'
    false
  else raise "bad bool #{s}"
  end
end

def toml(dir)
  toml = File.join(dir, '.meta', 'tests.toml')
  current_comments = []
  cases = []

  File.open(toml, ?r).each { |line|
    if line.start_with?(?#)
      current_comments << line[1..].strip.freeze
    elsif TEST_CASE.match(line)
      cases << TestCase.new($1, current_comments.freeze, bool($2))
      current_comments = []
    end
  }

  cases.to_h { |c| [c.uuid, c] }
end

def flat_cases(cases)
  cases.flat_map { |c|
    c['cases'] ? flat_cases(c['cases']) : c
  }
end

Diff = Struct.new(:uuid, :desc)

def exercise(dir)
  slug = File.basename(dir)
  canonical_data = File.join(dir, '..', '..', '..', 'problem-specifications', 'exercises', slug, 'canonical-data.json')
  return unless File.exist?(canonical_data)
  json = JSON.parse(File.read(canonical_data))
  cases = flat_cases(json['cases'])

  toml = toml(dir)

  # TODO
  diff = cases.map { |json_case|
    uuid = json_case['uuid']

    next Diff.new(uuid, "not in track's TOML. upstream desc: #{json_case['description']}") unless (toml_case = toml[uuid])

    unless toml_case.comments_above.any? { |x| x.strip == json_case['description'].strip }
      Diff.new(uuid, "description changed. new desc is: #{json_case['description']}")
    end
  }.compact

  return if diff.empty?

  puts slug
  diff.each { |d| puts "#{d.uuid}: #{d.desc}" }
  puts
end

if ARGV.empty?
  git_root = `git rev-parse --show-toplevel`.strip
  raise 'must run with args, or run in git repo without args' if git_root.empty?
  ARGV << File.join(git_root, 'exercises')
end

ARGV.each { |arg|
  if File.basename(arg) == 'exercises'
    exercises = Dir.glob(File.join(arg, '*/')).sort
    exercises.each { |x| exercise(x) }
  else
    exercise(arg)
  end
}
