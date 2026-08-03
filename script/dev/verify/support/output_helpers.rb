require "term/ansicolor"

module OutputHelpers
  include Term::ANSIColor

  def pass(msg)
    puts green("  PASS  #{msg}")
  end

  def fail(msg)
    puts red("  FAIL  #{msg}")
  end

  def section(title)
    puts cyan("\n== #{title} ==")
  end

  def info(msg)
    puts yellow("  INFO  #{msg}")
  end

  def separator
    puts cyan("-" * 60)
  end

  extend self
end
