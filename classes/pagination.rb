class Paginator
  attr_reader :page, :per_page

  def initialize(params, per_page, custom_name = 'p')
    @current_page = params[custom_name].nil? || params[custom_name].to_i < 1 ? 1 : params[custom_name].to_i
    @per_page = per_page
  end

  def get_page(items)
    start_index = (@current_page - 1) * @per_page
    items[start_index, @per_page]
  end

  def pages_info(items)
    total_pages = (items.length / @per_page.to_f).ceil
    (1..total_pages).map do |page_number|
      { page: page_number, is_current: page_number == @current_page }
    end
  end
end
