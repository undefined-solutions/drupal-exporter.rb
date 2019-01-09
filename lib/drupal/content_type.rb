module Contentful
  module Exporter
    module Drupal
      class ContentType

        attr_reader :exporter, :config, :type, :schema

        def initialize(exporter, config, type, schema)
          @exporter = exporter
          @config = config
          @type = type
          @schema = schema
        end

        def save_content_types_as_json
          exporter.create_directory("#{config.entries_dir}/#{type}")
          config.db[:node].where(type: type).each do |content_row|
            extract_data(content_row)
          end
        end

        private

        def extract_data(content_row)
          puts "Saving #{type} - id: #{content_row[:nid]}"
          db_object = map_fields(content_row)
          exporter.write_json_to_file("#{config.entries_dir}/#{type}/#{db_object[:id]}.json", db_object)
        end

        def map_fields(row, result = {})
          result.merge!(set_default_data(row))
          result.merge!(find_related_data(row))
          result
        end

        def id(content_id)
          "#{type}_#{content_id}"
        end

        def author(user_id)
          {type: 'Author', id: "user_#{user_id}"}
        end

        def tags(entity_row_id)
          entity_tags(entity_row_id).each_with_object([]) do |tag, tags|
            linked_tag = {type: 'EntryTag', id: "tag_#{tag[:field_tags_tid]}"}
            tags << linked_tag
          end
        end

        def entity_tags(entity_id)
          config.db[:field_data_field_tags].where(entity_id: entity_id)
        end

        def set_default_data(row, result = {})
          result[:id] = id(row[:nid])
          result[:title] = row[:title]
          result[:author] = author(row[:uid])
          result[:tags] = tags(row[:nid]) unless tags(row[:nid]).empty?
          result[:created_at] = created_at(row[:created])
          result[:updated_at] = created_at(row[:changed])
          result
        end

        def find_related_data(row, result = {})
          schema.each do |key, column_name|
            if column_name.is_a?(String)
              result[key] = fetch_data_from_related_table(row[:nid], column_name)
            elsif column_name['type']
              result[key] = fetch_entity_relation(row[:nid], column_name)
            else
              result[key] = fetch_custom_tags(row[:nid], column_name)
            end
          end
          result
        end

        def fetch_data_from_related_table(entity_id, table_name)
          related_row = get_related_row(entity_id, table_name)
          fetch_data_from_related_row(related_row, table_name)
        end

        def fetch_data_from_related_row(related_row, table_name)
          respond_to_file?(related_row, table_name) ? get_file_id(related_row, table_name) : related_value(related_row, table_name)
        end

        def respond_to_file?(related_row, table_name)
          file_id = "#{table_name}_fid".to_sym
          (related_row.present? && related_row.first[file_id]) ? true : false
        end

        def get_file_id(related_row, table_name)
          file_key = "#{table_name}_fid".to_sym
          related_row.each_with_object([]) do |file_relation, files|
            file_id = file_relation[file_key]
            file_asset_id = file_id(file_id)
            lined_file = link_asset_to_content_type(file_asset_id)
            files << lined_file
          end
        end

        def file_id(file_id)
          config.db[:file_managed].where(fid: file_id).first[:fid]
        end

        def get_related_row(entity_id, table_name)
          config.db[related_table_name(table_name)].where(entity_id: entity_id)
        end

        def link_asset_to_content_type(file_asset_id)
          {type: 'File', id: "file_#{file_asset_id}"}
        end

        def related_value(related_rows, table_name)
          value = related_rows.empty? ? nil : related_rows.first[field_name(table_name)]
          convert_type_value(value, table_name)
        end

        def fetch_entity_relation(entity_id, table_name)
          relation_table = "field_data_#{table_name['table']}".to_sym
          node_id = "#{table_name['table']}_target_id".to_sym
          config.db[relation_table].where(entity_id: entity_id).each_with_object([]) do |content_relation, relations|
            lined_relation = {type: 'Entry', id: "#{table_name['type']}_#{content_relation[node_id]}"}
            relations << lined_relation
          end
        end

        def fetch_custom_tags(entity_id, table_name)
          custom_tag_table = "field_data_#{table_name['table']}".to_sym
          tag_id = "#{table_name['table']}_tid".to_sym
          config.db[custom_tag_table].where(entity_id: entity_id).each_with_object([]) do |content_tag, tags|
            lined_tags = {type: 'EntryTag', id: "tag_#{content_tag[tag_id]}"}
            tags << lined_tags
          end
        end

        def related_table_name(table_name)
          "field_data_#{table_name}".to_sym
        end

        def field_name(table_name)
          "#{table_name}_value".to_sym
        end

        def created_at(timestamp)
          Time.at(timestamp).to_datetime
        end

        def convert_type_value(value, column_name)
          if value.is_a?(BigDecimal)
            value.to_f
          elsif boolean_column?(column_name)
            convert_boolean_value(value)
          else
            value
          end
        end

        def boolean_column?(column_name)
          exporter.boolean_columns && exporter.boolean_columns.flatten.include?(column_name) ? true : false
        end

        def convert_boolean_value(value)
          if value.nil?
            nil
          elsif value.instance_of? String
            value == 'Yes' ? true : false
          else
            value == 1 ? true : false
          end
        end

      end
    end
  end
end