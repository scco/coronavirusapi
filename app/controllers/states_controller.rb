class StatesController < ApplicationController
  before_action :set_state, only: [:show, :edit, :update, :destroy]

  STATE_COUNT = 51
  H_POP = {"AL"=>4779736, "AK"=>710231, "AZ"=>6392017, "AR"=>2915918, "CA"=>37253956, "CO"=>5029196, "CT"=>3574097, 
  	"DE"=>897934, "DC"=>601723, "FL"=>18801310, "GA"=>9687653, "HI"=>1360301, "ID"=>1567582, "IL"=>12830632, 
  	"IN"=>6483802, "IA"=>3046355, "KS"=>2853118, "KY"=>4339367, "LA"=>4533372, "ME"=>1328361, "MD"=>5773552, 
  	"MA"=>6547629, "MI"=>9883640, "MN"=>5303925, "MS"=>2967297, "MO"=>5988144, "MT"=>989415, "NE"=>1826341, 
  	"NV"=>2700551, "NH"=>1316470, "NJ"=>8791894, "NM"=>2059179, "NY"=>19378102, "NC"=>9535483, "ND"=>672591, 
  	"OH"=>11536504, "OK"=>3751351, "OR"=>3831074, "PA"=>12702379, "RI"=>1052567, "SC"=>4625364, "SD"=>814180, 
  	"TN"=>6346165, "TX"=>25145561, "US"=>308745538, "UT"=>2763885, "VT"=>625741, "VA"=>8001024, "WA"=>6724540, 
  	"WV"=>1852994, "WI"=>5686986, "WY"=>563626}
  HOUR = 3600

  # deleted redudant data with:
  # h={};State.all.order(:crawled_at).map {|s| ((t,p,d=h[s.name])&&(t.to_i>=s.tested.to_i)&&(p.to_i>=s.positive.to_i)&&(d.to_i>=s.deaths.to_i)) ? s.delete : [h[s.name]=[s.tested,s.positive,s.deaths]]}
  # run this after migration:
  #   # State.all.each {|s| [s.crawled_at=s.created_at, s.save]}

DAY_SEC = 3600 * 24
WEEK_SEC = DAY_SEC * 7

def round10(x)
  (x.to_f*10).round.to_f/10
end

def get_info_for(xs, ys)
  y_log = ys.map {|y| Math.log((y>0 ? y : 1).to_f)}
  lineFit = LineFit.new
  lineFit.setData(xs.map{|x| x.to_f},y_log)
  logIntercept,logSlope = lineFit.coefficients
  doublingTime = Math.log(2.0)/logSlope
  { "logSlope":logSlope, "doublingTime":doublingTime }
end

def positive_doubling_time(st)
  arr = State.where("name='#{st}' and official_flag=true").order(crawled_at: :desc)
  week_ago = arr[0].crawled_at.to_i - WEEK_SEC
  arr = arr.select {|i| i.crawled_at.to_i > week_ago }
  h = {}
  arr.each {|i| h[i.positive] = i.crawled_at.to_i} # remove duplicate values, use earliest date
  arr = h.to_a.map {|v,t| [t, v]}.sort
  xs = arr.map {|t,v| t}
  ys = arr.map {|t,v| v}
  round10(get_info_for(xs, ys)[:doublingTime]/DAY_SEC)
end

  def state_detail
    if (@st = params['name'].to_s.upcase) && @st.size == 2
      @chart_tested = {}
      @chart_pos = {}
      @chart_deaths = {}  
      arr = State.where("official_flag is true and name='#{@st}'").order(:crawled_at).all.map do |i|

        @chart_tested[i.crawled_at] = i.tested
        @chart_pos[i.crawled_at] = i.positive
        @chart_deaths[i.crawled_at] = i.deaths
        [i.crawled_at.to_i, i.tested, i.positive, i.deaths]
      end
      @timestamp, @tested, @positive, @deaths = arr[-1]
    else
      render plain: 'invalid query'    
    end
  end

  # only reloads redis if called with ?reload=y
  def summary
    @population = H_POP
    @timestamp = State.where('official_flag is true').order(:crawled_at).last.crawled_at
    skip = false
    begin
      redis = Redis.new(host: "localhost")
      old = redis.get('state_summary_cache3')
      if (old && (old=eval(old)) && old.shift == @timestamp.to_s)
        # load old data
        @updated_date,
        @url,
        @tested,
        @positive,
        @deaths,
        @tested_unofficial,
        @positive_unofficial,
        @deaths_unofficial,
        @chart_tested,
        @chart_pos,
        @chart_deaths,
        @chart_states,
        @chart_states2,
        @tested_arr,
        @h_positive,
        @h_deaths,
        @h_tested_unofficial,
        @h_positive_unofficial,
        @h_deaths_unofficial,
        @dates_time_series,
        @updated_at,
        @positive_doubling_time = old
        skip = true
      end
    rescue => e
    end
    if !skip && params['reload']
      h_tested_state = Hash.new(0)
      h_pos_state = Hash.new(0)
      h_deaths_state = Hash.new(0)
      h_tested_time = Hash.new(0)
      h_pos_time = Hash.new(0)
      h_deaths_time = Hash.new(0)
      prev_time_tested = nil
      prev_time_pos = nil
      prev_time_deaths = nil
      @url = {}
      @dates_time_series = {}
      @updated_at = {}
      @positive_doubling_time = {}
      State.all.where('official_flag is true').order(crawled_at: :asc).each do |s|
        curr_time = Time.at((s.crawled_at.to_i/HOUR)*HOUR).to_i # truncate to hour   
        @dates_time_series[curr_time] = true
        @updated_at[s.name] = s.crawled_at.to_i
        @positive_doubling_time[s.name] = positive_doubling_time(s.name)
        if s.positive && s.positive > h_pos_state[s.name]
          h_pos_time[curr_time] = h_pos_time[prev_time_pos] - h_pos_state[s.name] + s.positive
          h_pos_state[s.name] = s.positive
          prev_time_pos = curr_time
          @url[s.name] = s.positive_source
        end
        if s.tested && s.tested > h_tested_state[s.name]
          h_tested_time[curr_time] = h_tested_time[prev_time_tested] - h_tested_state[s.name] + s.tested
          h_tested_state[s.name] = s.tested
          prev_time_tested = curr_time
        end
        if s.deaths && s.deaths > h_deaths_state[s.name]
          h_deaths_time[curr_time] = h_deaths_time[prev_time_deaths] - h_deaths_state[s.name] + s.deaths
          h_deaths_state[s.name] = s.deaths
          prev_time_deaths = curr_time
        end  
      end # s 
      @tested_arr = h_tested_state.to_a.sort
      @h_positive = h_pos_state
      @h_deaths = h_deaths_state
      @updated_date = Time.at(prev_time_pos).to_s

      @tested = h_tested_state.values.compact.sum
      @positive = h_pos_state.values.compact.sum
      @deaths = h_deaths_state.values.compact.sum

      # chart data for 5 charts
      @chart_tested = h_tested_time
      @chart_pos = h_pos_time
      @chart_deaths = h_deaths_time

      names = @h_positive.to_a.sort {|a,b| b[1].to_i <=> a[1].to_i}.map {|i| i[0]}[0..9]
      all_dates = {}
      states = names.map do |name|
        h = {}
        State.where("name='#{name}' and official_flag is true").order(:crawled_at).map {|s| all_dates[x=s.crawled_at.to_date.to_s] = true; h[x] = s.positive }
        [name, h]
      end
      all_dates = all_dates.keys.sort
      @chart_states = states.map do |name, h|
        data = {}
        prev_val = 0
        all_dates.each do |a|
          if h[a]
            data[a] = h[a]
            prev_val = h[a]
          else
            data[a] = prev_val
          end
        end
        {'name' => name,
         'data' => data
        }
      end
      names = @h_positive.to_a.sort {|a,b| b[1].to_f/H_POP[b[0]] <=> a[1].to_f/H_POP[a[0]]}.map {|i| i[0]}[0..9]
      all_dates = {}
      states = names.map do |name|
        h = {}
        State.where("name='#{name}' and official_flag is true").order(:crawled_at).map {|s| all_dates[x=s.crawled_at.to_date.to_s] = true; h[x] = (s.positive.to_f/H_POP[name.upcase]*1000_000_0).round.to_f/10 }
        [name, h]
      end
      all_dates = all_dates.keys.sort
      @chart_states2 = states.map do |name, h|
        data = {}
        prev_val = 0
        all_dates.each do |a|
          if h[a]
            data[a] = h[a]
            prev_val = h[a]
          else
            data[a] = prev_val
          end
        end
        {'name' => name,
         'data' => data
        }
      end

      # unofficial counts
      h_tested_state = Hash.new(0)
      h_pos_state = Hash.new(0)
      h_deaths_state = Hash.new(0)
      h_tested_time = Hash.new(0)
      h_pos_time = Hash.new(0)
      h_deaths_time = Hash.new(0)
      prev_time_tested = nil
      prev_time_pos = nil
      prev_time_deaths = nil
      State.all.order(crawled_at: :asc).each do |s|
        curr_time = Time.at((s.crawled_at.to_i/HOUR)*HOUR) # truncate to hour   
        if s.positive && s.positive > h_pos_state[s.name]
          h_pos_time[curr_time] = h_pos_time[prev_time_pos] - h_pos_state[s.name] + s.positive
          h_pos_state[s.name] = s.positive
          prev_time_pos = curr_time
          @url[s.name] = s.positive_source
        end
        if s.tested && s.tested > h_tested_state[s.name]
          h_tested_time[curr_time] = h_tested_time[prev_time_tested] - h_tested_state[s.name] + s.tested
          h_tested_state[s.name] = s.tested 
          prev_time_tested = curr_time
        end
        if s.deaths && s.deaths > h_deaths_state[s.name]
          h_deaths_time[curr_time] = h_deaths_time[prev_time_deaths] - h_deaths_state[s.name] + s.deaths
          h_deaths_state[s.name] = s.deaths 
          prev_time_deaths = curr_time
        end 
      end # s
      @h_tested_unofficial = h_tested_state
      @h_positive_unofficial = h_pos_state
      @h_deaths_unofficial = h_deaths_state

      @tested_unofficial = h_tested_state.values.compact.sum
      @positive_unofficial = h_pos_state.values.compact.sum
      @deaths_unofficial = h_deaths_state.values.compact.sum

      x = [@timestamp.to_s,
           @updated_date,
           @url,
           @tested,
           @positive,
           @deaths, 
           @tested_unofficial,
           @positive_unofficial,
           @deaths_unofficial,
           @chart_tested,
           @chart_pos,
           @chart_deaths,
           @chart_states,
           @chart_states2,
           @tested_arr,
           @h_positive,
           @h_deaths,
           @h_tested_unofficial,
           @h_positive_unofficial,
           @h_deaths_unofficial,
           @dates_time_series,
           @updated_at,
           @positive_doubling_time].to_s
      redis.set("state_summary_cache3", x) rescue nil
    end # unless skip
    
    # fix time in 3 charts
    h = {}
    @chart_tested.each {|k,v| h[Time.at(k)]=v}
    @chart_tested = h
    h = {}
    @chart_pos.each {|k,v| h[Time.at(k)]=v}
    @chart_pos = h
    h = {}
    @chart_deaths.each {|k,v| h[Time.at(k)]=v}
    @chart_deaths = h
  end

  def export_csv
    summary
    data = @tested_arr.map { |state_name, tested| [state_name, tested, @h_positive[state_name], @h_deaths[state_name]] }
    attributes = %w{name, tested positive deaths}
    out = CSV.generate(headers: true) do |csv|
      csv << attributes
      data.each { |i| csv << i}
    end
    respond_to do |format|
      format.csv { send_data out, filename: "states.csv" }
    end
  end

  def export_time_series_csv
    summary
    tested = pos = deaths = 0
    data = @dates_time_series.keys.map do |t|
      s = Time.at(t).to_s
      t2 = Time.at t
      [s[0..9], s[11..18], t, 
       @chart_tested[t2] ? (tested=@chart_tested[t2]) : tested, 
       @chart_pos[t2] ? (pos=@chart_pos[t2]) : pos, 
       @chart_deaths[t2] ? (deaths=@chart_deaths[t2]) : deaths]
    end
    attributes = %w{date time seconds_since_Epoch tested positive deaths}
    out = CSV.generate(headers: true) do |csv|
      csv << attributes
      data.each { |i| csv << i }
    end
    respond_to do |format|
      format.csv { send_data out, filename: "time_series.csv" }
    end
  end

  def export_all
    data = State.where('official_flag is true').order(:crawled_at).all.map {|s| [s.crawled_at.to_i, s.name, s.tested, s.positive, s.deaths]}
    attributes = %w{seconds_since_Epoch state tested positive deaths}
    out = CSV.generate(headers: true) do |csv|
      csv << attributes
      data.each { |i| csv << i}
    end
    respond_to do |format|
      format.csv { send_data out, filename: "export_all.csv" }
    end
  end

  def get_time_series
    if (st = params['name']) && st.size < 3
      s = "seconds_since_Epoch,tested,positive,deaths\n"
      arr = State.where("official_flag is true and name='#{st.upcase}'").order(:crawled_at).all.map {|i| [i.crawled_at.to_i, i.tested, i.positive, i.deaths].join(",")}
      if arr.size == 0
        s = "#{st} not found"
      else
        s += arr.join("\n")
      end
    else
      s = "Please use a 2 letter state abbreviation"
    end
    render plain: s
  end

  # unused scaffolding code

  # GET /states
  # GET /states.json
  def index
    @states = State.all
  end

  # GET /states/1
  # GET /states/1.json
  def show
  end

  # GET /states/new
  def new
    @state = State.new
  end

  # GET /states/1/edit
  def edit
  end

  # POST /states
  # POST /states.json
  def create
    @state = State.new(state_params)

    respond_to do |format|
      if @state.save
        format.html { redirect_to @state, notice: 'State was successfully created.' }
        format.json { render :show, status: :created, location: @state }
      else
        format.html { render :new }
        format.json { render json: @state.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /states/1
  # PATCH/PUT /states/1.json
  def update
    respond_to do |format|
      if @state.update(state_params)
        format.html { redirect_to @state, notice: 'State was successfully updated.' }
        format.json { render :show, status: :ok, location: @state }
      else
        format.html { render :edit }
        format.json { render json: @state.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /states/1
  # DELETE /states/1.json
  def destroy
    @state.destroy
    respond_to do |format|
      format.html { redirect_to states_url, notice: 'State was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_state
      @state = State.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def state_params
      params.require(:state).permit(:name, :tested, :positive, :deaths, :tested_crawl_date, :positive_crawl_date, :deaths_crawl_date, :tested_source, :positive_source, :deaths_source)
    end
  end
