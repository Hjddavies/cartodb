# encoding: utf-8

require_relative '../../services/carto/visualizations_export_service_2'
require_dependency 'carto/named_maps/api'

module Carto
  class Mapcap < ActiveRecord::Base
    include Carto::VisualizationsExportService2Importer
    include Carto::VisualizationsExportService2Exporter

    belongs_to :visualization, class_name: Carto::Visualization, foreign_key: 'visualization_id'

    before_save :generate_export_json, :generate_ids_json

    after_save :notify_map_change, :update_named_map
    after_destroy :notify_map_change

    def regenerate_visualization
      regenerated_visualization = build_visualization_from_json_export(export_json)

      regenerated_visualization.user = regenerated_visualization.map.user = visualization.user

      repopulate_ids(regenerated_visualization)
    end

    def ids_json
      JSON.load(self[:ids_json]).with_indifferent_access
    end

    def self.latest_for_visualizaiton(visualization_id)
      where(visualization_id: visualization_id).order('created_at DESC')
    end

    private

    def generate_export_json
      self.export_json = export_visualization_json_string(visualization_id, visualization.user)
    end

    def generate_ids_json
      self.ids_json = {
        visualization_id: visualization.id,
        map_id: visualization.map.id,
        layers: visualization.layers.map { |layer| { layer_id: layer.id, widgets: layer.widgets.map(&:id) } }
      }.to_json
    end

    def repopulate_ids(regenerated_visualization)
      regenerated_visualization.id = ids_json[:visualization_id]
      regenerated_visualization.map.id = ids_json[:map_id]

      regenerated_visualization.map.layers.each_with_index do |layer, index|
        stored_layer_ids = ids_json[:layers][index]
        stored_layer_id = stored_layer_ids[:layer_id]

        layer.id = stored_layer_id
        layer.maps = [regenerated_visualization.map]

        layer.widgets.each_with_index do |widget, widget_index|
          widget.id = stored_layer_ids[:widgets][widget_index]
          widget.layer_id = stored_layer_id
        end
      end

      regenerated_visualization
    end

    def notify_map_change
      visualization.map.notify_map_change
    end

    def update_named_map
      Carto::NamedMaps::Api.new(regenerate_visualization).update
    end
  end
end
