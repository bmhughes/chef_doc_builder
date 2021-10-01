#!/usr/bin/env ruby

require 'erb'
require 'fileutils'
require 'logger'
require 'optparse'

require_relative 'lib/chef_doc_builder'

def nil_or_empty_any?(*values)
  values.any? { |v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
end

$options = {
  doc_directory: nil,
  doc_directory_expand: nil,
  log_level: Logger::Severity::INFO,
  template_file: "#{__dir__}/templates/doc_template.erb",
  template_index_file: "#{__dir__}/templates/doc_index.erb",
  cookbook_prefix: Dir.pwd.split('/').last,
  resource_folder: "#{Dir.pwd}/resources",
  overwrite: false,
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} [$options]"

  opts.on('-h', '--help', 'Prints this help') do
    puts opts
    exit
  end

  opts.on('-r Dir', '--resource-directory Dir', 'Resource files directory') do |r|
    raise IOError, "Directory #{File.expand_path(r)} does not exist" unless Dir.exist?(File.expand_path(r))

    $options[:resource_folder] = File.expand_path(r)
  end

  opts.on('-t FILE', '--template FILE', 'Template file') do |t|
    raise IOError, "Template file #{File.expand_path(t)} does not exist" unless File.exist?(File.expand_path(t))

    $options[:template_file] = File.expand_path(t)
  end

  opts.on('-i FILE', '--index-template FILE', 'Index template file') do |i|
    raise IOError, "Template file #{File.expand_path(i)} does not exist" unless File.exist?(File.expand_path(i))

    $options[:template_index_file] = File.expand_path(i)
  end

  opts.on('-d Dir', '--doc-directory Dir', 'Documentation directory') do |d|
    $options[:doc_directory] = d
    $options[:doc_directory_expand] = File.expand_path(d)
  end

  opts.on('-o', '--overwrite', 'Overwrite existing markdown files') do
    $options[:overwrite] = true
  end

  opts.on('-p Prefix', '--cookbook-prefix Prefix', 'Cookbook prefix override') do |p|
    $options[:cookbook_prefix] = p
  end
end.parse!

$logger = Logger.new($stdout, level: $options[:log_level], progname: File.basename(__FILE__))

if nil_or_empty_any?($options[:template_file], $options[:doc_directory], $options[:doc_directory_expand])
  $logger.fatal('The template file must be set')
  exit 1
end

# Get resource files sans extention
files = Dir.children($options[:resource_folder]).filter { |f| File.extname(f).eql?('.rb') }.map { |f| File.basename(f, '.*') }.sort

# Build dummy resources
resources = files.map do |rf|
              dr = ChefDocBuilder::DummyResource.new("#{$options[:cookbook_prefix]}_#{rf}")
              dr.load_from_file("#{$options[:resource_folder]}/#{rf}.rb")

              dr
            end

# Render Templates
FileUtils.mkdir_p($options[:doc_directory_expand]) unless Dir.exist?($options[:doc_directory_expand])

resources.each do |resource|
  filename = "#{resource.name}.md"
  if File.exist?(File.join($options[:doc_directory_expand], filename)) && !$options[:overwrite]
    $logger.info("File #{filename} exists and overwrite is not set")
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

  file_content = ERB.new(File.read($options[:template_file]), trim_mode: '<>').result_with_hash(variables)
  File.write(File.join($options[:doc_directory_expand], filename), file_content)
end

# Index
variables = {}
variables['resources'] = files.map do |file|
              { 'name' => "#{$options[:cookbook_prefix]}_#{file}", 'path' => File.join($options[:doc_directory], "#{$options[:cookbook_prefix]}_#{file}.md") }
            end

file_content = ERB.new(File.read($options[:template_index_file]), trim_mode: '<>').result_with_hash(variables)
File.write(File.join($options[:doc_directory_expand], 'README.md'), file_content)
