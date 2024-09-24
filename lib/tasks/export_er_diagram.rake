# lib/tasks/export_er_diagram.rake
# run 
# #
# % docker compose exec redmine rails export:entity_relationship_diagram_plantuml
# 
# lib/tasks/export_er_diagram.rake

namespace :export do
  desc 'Exports the entity-relationship diagram using PlantUML'
  task entity_relationship_diagram_plantuml: :environment do
    # 全てのモデルをロード
    Rails.application.eager_load!
    ActiveRecord::Base.descendants.each(&:inspect)

    # モデルクラスを取得
    model_classes = ActiveRecord::Base.descendants.select { |m| m.table_name.present? }
    class_name_model_class_pair = model_classes.index_by { |m| m.name }
    relation_entity_components = Set.new
    entity_component_fields = Set.new
    unique_index_table_columns = Set.new
    foreign_key_pairs = {}

    # ER図のリレーションを構築
    class_name_model_class_pair.values.each do |model_class|
      model_class.reflections.values.each do |relation_info|
        # polymorphic の belongs_to はスキップ
        next if relation_info.polymorphic?

        if relation_info.instance_of?(ActiveRecord::Reflection::BelongsToReflection)
          to_model_class = model_class
          from_model_class = class_name_model_class_pair[relation_info.class_name]
        else
          from_model_class = model_class
          to_model_class = class_name_model_class_pair[relation_info.class_name]
        end

        # from_model_class または to_model_class が nil の場合はスキップ
        if from_model_class.nil? || to_model_class.nil?
          puts "Warning: Missing model class for relation:"
          puts "  Model: #{model_class.name}"
          puts "  Relation: #{relation_info.name}"
          puts "  Class Name: #{relation_info.class_name}"
          next
        end

        primary_keys = [from_model_class.primary_key].flatten
        to_foreign_key_string = [to_model_class.table_name, relation_info.foreign_key].join('.')
        if relation_info.options[:primary_key].present?
          from_foreign_key_string = [from_model_class.table_name, relation_info.options[:primary_key]].join('.')
        else
          from_foreign_key_string =
            primary_keys.map { |primary_key| [from_model_class.table_name, primary_key].join('.') }.join(',')
        end

        # 外部キーの関係を記録
        foreign_key_pairs[to_foreign_key_string] = from_foreign_key_string

        # リレーションの種類に応じてER図の表現を追加
        if relation_info.instance_of?(ActiveRecord::Reflection::HasManyReflection)
          relation_entity_components << [from_model_class.table_name, '--o{', to_model_class.table_name].join(' ')
        elsif relation_info.instance_of?(ActiveRecord::Reflection::HasOneReflection)
          relation_entity_components.delete(
            [from_model_class.table_name, '--o{', to_model_class.table_name].join(' '),
          )
          relation_entity_components << [from_model_class.table_name, '|o--o|', to_model_class.table_name].join(' ')
        elsif relation_info.instance_of?(ActiveRecord::Reflection::ThroughReflection)
          relation_entity_components << [from_model_class.table_name, '}o--o{', to_model_class.table_name].join(' ')
        elsif relation_info.instance_of?(ActiveRecord::Reflection::BelongsToReflection)
          unless relation_entity_components.include?(
                   [from_model_class.table_name, '|o--o|', to_model_class.table_name].join(' '),
                 )
            relation_entity_components << [from_model_class.table_name, '--o{', to_model_class.table_name].join(' ')
          end
        end
      end

      # インデックスの情報を取得
      model_class.connection.indexes(model_class.table_name).each do |index_definition|
        if index_definition.unique && index_definition.columns.size == 1
          unique_index_table_column = [model_class.table_name, index_definition.columns.first].join('.')
          unique_index_table_columns << unique_index_table_column
        end
      end
    end

    # エンティティの情報を構築
    class_name_model_class_pair.values.each do |model_class|
      primary_keys = [model_class.primary_key].flatten
      entity_components = []
      entity_components << ['entity', '"' + model_class.table_name + '"', '{'].join(' ')
      model_class.columns.each do |model_column|
        table_column_string = [model_class.table_name, model_column.name].join('.')
        if primary_keys.include?(model_column.name)
          entity_components << ['+', model_column.name, '[PK]', model_column.sql_type].join(' ')
          entity_components << '=='
        elsif foreign_key_pairs[table_column_string].present?
          entity_components <<
            [
              '#',
              model_column.name,
              '[FK(' + foreign_key_pairs[table_column_string] + ')]',
              model_column.sql_type,
            ].join(' ')
        elsif unique_index_table_columns.include?(table_column_string)
          entity_components << ['*', model_column.name, model_column.sql_type].join(' ')
        else
          entity_components << [model_column.name, model_column.sql_type].join(' ')
        end
      end
      entity_components << '}'
      entity_components << "\n"
      entity_component_fields << entity_components.join("\n")
    end

    # PlantUMLの記述を生成
    plntuml_components = Set.new
    plntuml_components << '```plantuml'
    plntuml_components << '@startuml'
    plntuml_components += entity_component_fields
    plntuml_components += relation_entity_components
    plntuml_components << '@enduml'
    plntuml_components << '```'
    export_plantuml_path = Rails.root.join('doc/er-diagram.pu')
    File.write(export_plantuml_path, plntuml_components.to_a.join("\n"))
  end
end
