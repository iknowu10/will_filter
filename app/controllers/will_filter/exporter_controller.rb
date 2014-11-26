#--
# Copyright (c) 2010-2013 Michael Berkovich
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'iconv'
require 'csv'

module WillFilter
  class ExporterController < ApplicationController

    WINDOWS_UTF16LE_BOM = "\377\376"

    def index
      @wf_filter = WillFilter::Filter.deserialize_from_params(params)
      @wf_filter.session_store = JSON.parse(session[:wf_filter_session_store], {:symbolize_names => true})
      @wf_filter.current_organisation_id = session[:current_organisation_id]
      render :layout => false
    end
  
    def export
      params[:page] = 1
      params[:wf_per_page] = 20000 # max export limit
  
      @wf_filter = WillFilter::Filter.deserialize_from_params(params)
      @wf_filter.session_store = JSON.parse(session[:wf_filter_session_store], {:symbolize_names => true})
      @wf_filter.current_organisation_id = session[:current_organisation_id]
      
      if @wf_filter.custom_format?
        send_data(@wf_filter.process_custom_format,
                  :type => 'text',
                  :charset => 'utf-8',
                  :disposition => 'attachment',
                  :filename => "#{file_system_safe(report_filter_name)}_#{Time.now.strftime("%Y-%m-%d %l:%M:%S")}.#{params[:wf_export_format]}")
        return
      end
      
      unless @wf_filter.valid_format?
        render :text => "The export format is not supported (#{@wf_filter.format})"
        return     
      end
      
      if @wf_filter.format == :xml
        return send_xml_data
      end  
  
      if @wf_filter.format == :json
        return send_json_data
      end  
      
      if @wf_filter.format == :csv
        return send_csv_data
      end  
  
      render :layout => false
    end  
  
    private

    def filter_results
      @wf_filter.results.map do |obj|
        @wf_filter.fields.each.inject({}) do |h,field|
          h.merge({field => obj.send(field).to_s})
        end
      end
    end
  
    def send_xml_data
      send_data(filter_results.to_xml, :type => 'text/xml', :charset => 'utf-8')
    end  
  
    def send_json_data
      send_data(filter_results.to_json, :type => 'text', :charset => 'utf-8')
    end  
    
    def send_csv_data
      csv_string = CSV.generate(:col_sep => "\t", :row_sep => "\r\n", :headers => true, :force_quotes => true) do |csv|
        csv << execution_time
        csv << report_name
        csv << @wf_filter.fields.map{|f| @wf_filter.condition_title_for(f)}
        @wf_filter.results.each do |obj|
          csv << @wf_filter.fields.map {|field| obj.send(field)}
        end
      end

      send_data WINDOWS_UTF16LE_BOM + Iconv.conv("utf-16le", "utf-8", csv_string), :type => 'text/csv; charset=utf-8; header=present', :charset => 'utf-8',
                            :disposition => "attachment; filename=results.csv"      
    end

    def report_name
      [I18n.t('operational_reports.labels.report_name'), report_filter_name]
    end

    def report_filter_name
      @wf_filter.name.present? ? @wf_filter.name : report_default_filter_name || report_title
    end

    def report_default_filter_name
      params[:wf_key] && params[:wf_key] != '-1' ? I18n.t("operational_reports.default_filters.#{params[:wf_model].demodulize.downcase}.#{params[:wf_key]}") : nil
    end

    def report_title
      I18n.t("operational_reports.report_titles.#{params[:wf_model].demodulize.underscore}")
    end

    def execution_time
      [I18n.t('operational_reports.labels.report_time'), Time.now.strftime("%Y-%m-%d %l:%M:%S")]
    end

    def action_time_limit
      180
    end

    def file_system_safe(name)
      name.downcase.gsub(/[\s\/\\:\*\?"<>|-]/, '_').force_encoding('UTF-8')
    end
  end
end