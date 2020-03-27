class AddDefaultCrawledAtValue < ActiveRecord::Migration[6.0]
  def change
    State.where(crawled_at:nil).update_all('crawled_at = created_at')
    change_column_default(
        :states,
        :crawled_at,
        from: nil,
        to: DateTime.now
    )
  end

end
