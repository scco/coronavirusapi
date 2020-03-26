class StaticPagesController < ApplicationController
  HOUR = 3600
  def show
    @updated_date= Time.at((State.all.where('official_flag is true').order(crawled_at: :desc)[0].crawled_at.to_i/HOUR)*HOUR).to_s
    render params[:page]
  end
end
