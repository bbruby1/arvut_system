module StreamWidget
  class Apotomo::Widget
    include StreamWidget::StreamHelper
    StreamHelper.instance_methods(false).each do |method|
      helper_method method
    end
  end

  class AdminContainer < Apotomo::Widget
    # responds_to_event :presetUpdated, :with => :redraw

    after_add do |me, parent|
      me.root.respond_to_event :presetUpdated, :with => :redraw, :on => me.name
    end
    
    has_widgets do |me|
      me << widget('stream_widget/admin_stream_preset', 'admin_form', :display)
      me.respond_to_event :new_preset, :with => :new, :on => 'admin_form'
      me.respond_to_event :edit_preset, :with => :edit, :on => 'admin_form'
    end
    
    def display
      @current_preset = current_preset
      @stream_presets = StreamPreset.all
      render
    end
    
    def redraw
      @stream_presets = StreamPreset.all
      render
    end
    
  end

  class AdminStreamPreset < Apotomo::Widget
    responds_to_event :submit, :with => :process_form
    

    def display
      @stream_preset = current_preset
      render
    end
    
    def new
      @stream_preset = StreamPreset.new
      3.times do
        @stream_preset.stream_items << StreamItem.new
      end
      replace :view => :display
    end

    def edit
      @stream_preset = StreamPreset.find(param(:stream_preset_id))
      replace :view => :display
    end
    
    def process_form
      if param(:stream_preset)[:id].empty?
        @stream_preset = StreamPreset.new
      else
        @stream_preset = StreamPreset.find(param(:stream_preset)[:id]) || StreamPreset.new
      end
      if @stream_preset.update_attributes(param(:stream_preset))
        trigger :presetUpdated
        update :text => "<span style=\"color:green;font-weight:bold;\">#{I18n.t 'kabtv.admin.successfully_saved'}</span>"
      else
        update :text => I18n.t(kabtv.admin.successfully_saved)
      end
    end
    
  end

  class Container < Apotomo::Widget
    include ActionView::Helpers::JavaScriptHelper
    responds_to_event :update_presets, :with => :process_request

    has_widgets do |me|
      me << widget('stream_widget/schedule', 'schedule', :display)
      me << widget('stream_widget/sketches', 'sketches', :display)
      me << widget('stream_widget/questions', 'questions', :display, :current_user => (param :current_user))
    end
    
    def display
      @stream_preset = current_preset
      @show_tabs = @stream_preset.show_questions || @stream_preset.show_sketches || @stream_preset.show_schedule
      @show_support = @stream_preset.show_support
      @languages = @stream_preset.stream_items.map(&:language_id).uniq
      @current_user = param :current_user
      render
    end

    def process_request
      stream_preset = current_preset
      timestamp = param :timestamp
      if stream_preset.updated_at.to_s == timestamp
        render :text => '', :content_type => Mime::JS
        return
      end

      # look for channel
      reload_player = ! stream_preset.stream_items.map{|p| p.stream_url}.include?(params[:stream_url])
      current_item = stream_preset.stream_items.select{|p| p.stream_url == params[:stream_url]}

      languages = stream_preset.stream_items.map(&:language_id).uniq
      presets = get_presets(stream_preset, languages, current_item)

      render :text => "
        #{"kabtv.tabs.timestamp = '#{stream_preset.updated_at.to_s}';".html_safe}
        #{"var presets_data = #{stream_preset.to_json};".html_safe}
        #{"var presets = #{presets.to_json};".html_safe}
        var reload_player = #{reload_player};
      ", :content_type => Mime::JS
    end

    def get_presets(stream_preset, languages, current_item)
      presets = {}
      languages.each{ |language_id|
        items = stream_preset.stream_items.select{|item|
          item.language_id == language_id && !item.description.empty? && !item.stream_url.empty?
        }
        options_list = []
        image = ''
        items.each {|item|
          if (!current_item.empty? && current_item[0].language_id == language_id)
            # this language
            is_default = current_item[0].stream_url == item.stream_url
          else
            is_default = item.is_default
          end
          options_list << "<option #{"selected='selected'".html_safe if is_default} value='#{item.stream_url}'>#{item.description}</option>"
          image = "<img src='#{item.inactive_image}' alt='#{I18n.t 'kabtv.kabtv.no_broadcast'}' />" unless item.inactive_image.empty?
        }
        presets[language_id] = {:options => options_list.join(','), :image => image}
      }

      presets
    end
  end
  
  private

  class Questions < Apotomo::Widget
    include ActionView::Helpers::JavaScriptHelper
    include ActionView::Helpers::AssetTagHelper
    alias_method(:controller, :parent_controller)
    
    responds_to_event :more_questions, :with => :process_request
    responds_to_event :submit_question, :with => :process_submit
    
    def display
      return unless current_preset.show_questions
      current_user = param :current_user
      @ask = CopyQuestion.new
      @ask.qname = [current_user.first_name, current_user.last_name].join(' ') rescue ''
      @ask.qfrom = [current_user.location.city, current_user.region.name, current_user.country.name].join(', ') rescue ''
      render
    end

    def process_request
      last_question_id = (param :last_question_id).to_i

      (@questions, @total_questions) = CopyQuestion.approved_questions(last_question_id)

      if @questions.empty?
        if last_question_id == 0
          # no questions => no questions
          render :text => '', :content_type => Mime::JS
        elsif @total_questions == 0
          # questions => no new questions
          render :text => "
            $('dl#questions').html('#{escape_javascript "<dd class='even'>#{I18n.t 'kabtv.kabtv.no_questions_yet'}</dd>".html_safe}');
            kabtv.questions.last_question_id = 0;
          ", :content_type => Mime::JS
        else
          render :text => '', :content_type => Mime::JS
        end
      else
        content = ''
        @questions.each_with_index {|q, idx|
          klass = ((last_question_id + 1 + idx) & 1) == 0 ? 'odd' : 'even'
          name = q.qname.empty? ? I18n.t('kabtv.kabtv.guest') : q.qname
          from = q.qfrom.empty? ? I18n.t('kabtv.kabtv.somewhere') : q.qfrom
          style = q.lang == 'Hebrew' ? 'style="direction:rtl"' : ''
          if q.stimulator_id.to_i > 0
            user = User.find(q.stimulator_id)
            img = "<img src='#{image_path user.avatar_url(:thumb)}' />"
          else
            img = "<img src='#{image_path 'user.png'}' />"
          end

          content += <<-HTML
            <dt class="#{klass}" #{style}>#{img}<span class="who">#{name}</span> @ <span class="where">#{from}</span></dt>
            <dd class="#{klass}" #{style}>#{q.qquestion}</dd>
          HTML
        }
        if last_question_id == 0
          # no questions => questions
          render :text => "
            $('dl#questions').html('#{escape_javascript content.html_safe}');
            kabtv.questions.last_question_id = #{@questions.last.id};
          ", :content_type => Mime::JS
        else
          # questions => more questions
          render :text => "
            $('dl#questions').append('#{escape_javascript content.html_safe}');
            kabtv.questions.last_question_id =+ #{@questions.last.id};
          ", :content_type => Mime::JS
        end
      end
    end

    def process_submit
      if CopyQuestion.ask_question(param(:kabtv_question), param(:current_user))
        message = I18n.t 'kabtv.kabtv.awaiting_for_approval'
        render :text => "alert('#{message}');", :content_type => Mime::JS
      else
        message = I18n.t 'kabtv.kabtv.no_question'
        render :text => "kabtv.questions.toggleAskAndQuestions();alert('#{message}');", :content_type => Mime::JS
      end
    end
  end

  class Schedule < Apotomo::Widget
    include ActionView::Helpers::JavaScriptHelper

    def display
      return unless current_preset.show_schedule

      @days = Date::DAYNAMES
      @schedules = {}
      language = Kabtv.map_locale_2_language(I18n.locale)
      @days.each { |weekday|
        @schedules[weekday] = generate_schedule(weekday, language)
      }
      render
    end

    private

    def generate_schedule(weekday, language)
      alist = CopyListing.get_day(weekday, language)
      return "<h3>#{I18n.t 'no_broadcast_on'}#{weekday}</h3>" if alist.empty?
      
      list = "<div class='hdr'>#{CopyDates.get_day(weekday, language)}</div><table>"
      alist.each_with_index { |item, index|
        time = sprintf("<td class='time'>%02d:%02d</td>",
          item.start_time / 100,
          item.start_time % 100)
        title = item.title.gsub '[\r\n]', ''
        title.gsub! '<div>', ''
        title.gsub! '</div>', ''
        descr = item.descr.gsub '[\r\n]', ''
        descr.gsub!(/href=([^"])(\S+)/, 'href="\1\2" ')
        descr.gsub!('target=_blank', 'class="target_blank"')
        descr.gsub!('target="_blank"', 'class="target_blank"')
        descr.gsub!('&main', '&amp;main')
        descr.gsub!('<br>', '<br/>')
        descr.gsub!(/<font\s+color\s*=\s*["\'](\w+)["\']>/, '<span style="color:\1">')
        descr.gsub!(/<font\s+color\s*=\s*["\'](#[0-9A-Fa-f]+)["\']>/, '<span style="color:\1">')
        descr.gsub!('</font>', '</span>')

        list += "<tr>#{time}<td class='title item#{index & 1}'>#{title}<br/>#{descr}</td></tr>"
      }
      list += "</table>"

      list.html_safe
    end

  end

  class Sketches < Apotomo::Widget
    responds_to_event :classboard, :with => :display_classboard
    
    def display
      return unless current_preset.show_sketches

      render
    end

    def display_classboard
      images = []
      reset = false
      begin
        data = EventDataReader::ClassBoard.new.classboard
        sketches_url = data[:urls][:sketches]
        sketches = data[:thumbnails]
        last_one = params[:total].to_i
        total = sketches.size
        reset = last_one > total
        sketches = reset ? sketches : (sketches[last_one .. total] || [])
        images = sketches.map{ |img|
          "<img alt='' src='#{sketches_url}/#{img}'></img>"
        }
      end
      text = if images.empty? && !reset
        # Nothing to show (and it was not reset)
        total == 0 ?
          # No sketches on server
          '$(\'.images\').html(\'\')' :
            # No new sketches
          ''
      else
        reset ?
          # Less files... Or reset had happened or some images were removed
          "$('.images').html('#{escape_javascript images.join('').html_safe}');" :
          # New files were added
          "$('.images').append('#{escape_javascript images.join('').html_safe}');"
      end
      render :text => text, :content_type => Mime::JS
    end
  end
end
