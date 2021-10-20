#!/usr/bin/env ruby

require 'erb'
require 'fileutils'
require 'logger'
require 'optparse'

require_relative 'lib/chef_doc_builder'

VERSION = '0.1.0'.freeze

def nil_or_empty_any?(*values)
  values.any? { |v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
end

# Note - These are escaped Symbol, not String as optparse returns key names with dashes
$options = {
  "doc-directory": nil,
  "log-level": Logger::Severity::INFO,
  "template-file": "#{__dir__}/templates/doc_template.erb",
  "template-index-file": "#{__dir__}/templates/doc_index.erb",
  "cookbook-prefix": Dir.pwd.split('/').last,
  "resource-directory": "#{Dir.pwd}/resources",
  "overwrite": false,
}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} [$options]"

  opts.on_head('-h', '--help', 'Prints this help') do
    puts opts
    exit
  end

  opts.on_head('-l Level', '--log-level=Level', String, 'Set script log level') { |v| Object.const_get("Logger::Severity::#{v.upcase}") }

  opts.on_head('-v', '--version', 'Show version and exit') do
    puts VERSION
    exit
  end

  opts.separator("")
  opts.separator "Docs builder options:"

  opts.on('-d DIR', '--doc-directory=DIR', String, :REQUIRED, 'Documentation directory (Required)') do |d|
    if nil_or_empty_any?(File.expand_path(d))
      $logger.fatal("Unable to expand the supplied documentation directory #{d}!")
      exit 2
    end

    File.expand_path(d)
  end

  opts.on('-f File', '--resource-file=File', 'Resource file for single documentation generation') do |r|
    raise IOError, "File #{File.expand_path(r)} does not exist" unless File.exist?(File.expand_path(r))

    File.expand_path(r)
  end

  opts.on('-i File', '--index-template=File', String, 'Index template file (Defaults to templates/doc_index.erb)') do |i|
    raise IOError, "Template file #{File.expand_path(i)} does not exist" unless File.exist?(File.expand_path(i))

    File.expand_path(i)
  end

  opts.on('-o', '--overwrite', 'Overwrite existing markdown files')
  opts.on('-p Prefix', '--cookbook-prefix=Prefix', 'Cookbook prefix override (Defaults to current directory name)')

  opts.on('-r Dir', '--resource-directory=Dir', String, 'Resource files directory (Defaults to ./resources)') do |r|
    raise IOError, "Directory #{File.expand_path(r)} does not exist" unless Dir.exist?(File.expand_path(r))

    File.expand_path(r)
  end

  opts.on('-t File', '--template=File', String, 'Template file (Defaults to templates/doc_template.erb)') do |t|
    raise IOError, "Template file #{File.expand_path(t)} does not exist" unless File.exist?(File.expand_path(t))

    File.expand_path(t)
  end
end

optparse.parse!(into: $options)

$logger = Logger.new($stdout, level: $options[:"log-level"], progname: File.basename(__FILE__))

# Check for required options
begin
  $logger.debug("Parsed options: \n#{$options}")

  missing_opts = %i(doc-directory).filter { |o| nil_or_empty_any?($options.fetch(o, nil)) }
  $logger.debug("Found missing options: #{missing_opts.join(', ')}")

  raise OptionParser::MissingArgument.new(missing_opts.join(', ')) unless missing_opts.empty?
rescue OptionParser::InvalidOption, OptionParser::MissingArgument
  $logger.fatal($!.to_s)
  puts("\n#{optparse}\n")
  exit 1
end

# Get resource files sans extention
begin
  files = if $options[:"resource-file"]
            Array(File.basename($options[:"resource-file"], '.*'))
          else
            Dir.children($options[:"resource-directory"]).filter { |f| File.extname(f).eql?('.rb') }.map { |f| File.basename(f, '.*') }.sort
          end
rescue Errno::ENOENT
  $logger.fatal("Unable to open resource directory #{$options[:"resource-directory"]}")
  exit 3
end

# Build dummy resources
$logger.info("Building dummy resources from #{files.count} custom resource definitions")
resources = files.map { |rf| ChefDocBuilder::DummyResource.new("#{$options[:"cookbook-prefix"]}_#{rf}").load_from_file("#{$options[:"resource-directory"]}/#{rf}.rb") }

# Render Templates
FileUtils.mkdir_p($options[:"doc-directory"]) unless Dir.exist?($options[:"doc-directory"])
doc_count = 0

resources.each do |resource|
  filename = "#{resource.name}.md"
  if File.exist?(File.join($options[:"doc-directory"], filename)) && !$options[:overwrite]
    $logger.info("Skip creating doc file #{filename} as it already exists and overwrite is not set")
    next
  end

  $logger.info("Write file #{filename}")

  variables = {
    resource_name: filename.delete_suffix('.md'),
    actions: resource.actions,
    libraries: resource.libraries,
    properties: resource.properties,
    uses: resource.uses
  }
  $logger.debug("Write file vars #{variables}")

  file_content = ERB.new(File.read($options[:"template-file"]), trim_mode: '<>').result_with_hash(variables)
  File.write(File.join($options[:"doc-directory"], filename), file_content)
  doc_count += 1
end

$logger.info("Wrote #{doc_count} doc files")

# Index
if (File.exist?(File.join($options[:"doc-directory"], 'README.md')) && !$options[:overwrite]) || $options[:"resource-file"]
  $logger.info("Skip creating README index file as it already exists and overwrite is not set")
else
  $logger.info("Updating index file for #{doc_count} doc files")
  variables = {}
  variables['resources'] = files.map do |file|
                             { 'name' => "#{$options[:"cookbook-prefix"]}_#{file}", 'path' => File.join($options[:"doc-directory"], "#{$options[:"cookbook-prefix"]}_#{file}.md") }
                           end

  file_content = ERB.new(File.read($options[:"template-index-file"]), trim_mode: '<>').result_with_hash(variables)
  File.write(File.join($options[:"doc-directory"], 'README.md'), file_content)
end
