local Date = require('orgmode.objects.date')
local Files = require('orgmode.parser.files')
local Range = require('orgmode.parser.range')
local config = require('orgmode.config')
local ClockReport = require('orgmode.clock.report')
local AgendaItem = require('orgmode.agenda.agenda_item')
local AgendaFilter = require('orgmode.agenda.filter')
local utils = require('orgmode.utils')
local AgendaView = {}

---@param agenda_items AgendaItem[]
---@return AgendaItem[]
local function sort_agenda_items(agenda_items)
  table.sort(agenda_items, function(a, b)
    if a.is_today and a.is_same_day then
      if b.is_today and b.is_same_day then
        return a.headline_date:is_before(b.headline_date)
      end
      return true
    end

    if b.is_today and b.is_same_day then
      if a.is_today and a.is_same_day then
        return a.headline_date:is_before(b.headline_date)
      end
      return false
    end

    if a.headline:get_priority_sort_value() ~= b.headline:get_priority_sort_value() then
      return a.headline:get_priority_sort_value() > b.headline:get_priority_sort_value()
    end

    if a.headline:has_priority() and b.headline:has_priority() then
      return a.headline_date:is_before(b.headline_date)
    end

    if a.is_in_date_range and not b.is_in_date_range then
      return false
    end

    if not a.is_in_date_range and b.is_in_date_range then
      return true
    end

    return a.headline_date:is_before(b.headline_date)
  end)
  return agenda_items
end

function AgendaView:new(opts)
  opts = opts or {}
  local data = {
    content = {},
    highlights = {},
    items = {},
    span = opts.span or config:get_agenda_span(),
    from = opts.from or Date.now():start_of('day'),
    to = opts.to,
    search = opts.search or '',
    filters = AgendaFilter:new(),
    show_clock_report = opts.show_clock_report or false,
    start_on_weekday = opts.org_agenda_start_on_weekday or config.org_agenda_start_on_weekday,
    start_day = opts.org_agenda_start_day or config.org_agenda_start_day,
    header = opts.org_agenda_overriding_header,
  }
  setmetatable(data, self)
  self.__index = self
  data:_set_date_range()
  return data
end

function Agenda:_get_title()
  if self.header then
    return self.header
  end
  local span = self.span
  if type(span) == 'number' then
    span = string.format('%d days', span)
  end
  local span_number = ''
  if span == 'week' then
    span_number = string.format(' (W%d)', self.from:get_week_number())
  end
  return utils.capitalize(span) .. '-agenda' .. span_number .. ':'
end

function AgendaView:_set_date_range(from)
  local span = self.span
  from = from or self.from
  local is_week = span == 'week' or span == '7'
  if is_week and self.start_on_weekday then
    from = from:set_isoweekday(self.start_on_weekday)
  end
  local to = self.to

  if not to then
    local modifier = { [span] = 1 }
    if type(span) == 'number' then
      modifier = { day = span }
    end

    to = from:add(modifier)
  end

  if self.start_day and type(self.start_day) == 'string' then
    from = from:adjust(self.start_day)
    to = to:adjust(self.start_day)
  end

  self.span = span
  self.from = from
  self.to = to
end

function AgendaView:open()
  local dates = self.from:get_range_until(self.to)
  local agenda_days = {}

  local headline_dates = {}
  for _, orgfile in ipairs(Files.all()) do
    for _, headline in ipairs(orgfile:get_opened_headlines()) do
      for _, headline_date in ipairs(headline:get_valid_dates_for_agenda()) do
        table.insert(headline_dates, {
          headline_date = headline_date,
          headline = headline,
        })
      end
    end
  end

  for _, day in ipairs(dates) do
    local date = { day = day, agenda_items = {} }

    for _, item in ipairs(headline_dates) do
      local agenda_item = AgendaItem:new(item.headline_date, item.headline, day)
      if agenda_item.is_valid and self.filters:matches(item.headline) then
        table.insert(date.agenda_items, agenda_item)
      end
    end

    date.agenda_items = sort_agenda_items(date.agenda_items)

    table.insert(agenda_days, date)
  end

  self.items = agenda_days
  self:render_agenda()
  vim.fn.search(self:_format_day(Date.now()))
end

function AgendaView:render_agenda()
  local content = { { line_content = self:_get_title() } }
  local highlights = {}
  for _, item in ipairs(self.items) do
    local day = item.day
    local agenda_items = item.agenda_items

    local is_today = day:is_today()
    local is_weekend = day:is_weekend()

    if is_today or is_weekend then
      table.insert(highlights, {
        hlgroup = 'OrgBold',
        range = Range:new({
          start_line = #content + 1,
          end_line = #content + 1,
          start_col = 1,
          end_col = 0,
        }),
      })
    end

    table.insert(content, { line_content = self:_format_day(day) })

    local longest_items = utils.reduce(agenda_items, function(acc, agenda_item)
      acc.category = math.max(acc.category, agenda_item.headline:get_category():len())
      acc.label = math.max(acc.label, agenda_item.label:len())
      return acc
    end, {
      category = 0,
      label = 0,
    })
    local category_len = math.max(11, (longest_items.category + 1))
    local date_len = math.min(11, longest_items.label)

    for _, agenda_item in ipairs(agenda_items) do
      local headline = agenda_item.headline
      local category = string.format('  %-' .. category_len .. 's', headline:get_category() .. ':')
      local date = agenda_item.label
      if date ~= '' then
        date = string.format(' %-' .. date_len .. 's', agenda_item.label)
      end
      local todo_keyword = agenda_item.headline.todo_keyword.value
      local todo_padding = ''
      if todo_keyword ~= '' and vim.trim(agenda_item.label):find(':$') then
        todo_padding = ' '
      end
      todo_keyword = todo_padding .. todo_keyword
      local line = string.format('%s%s%s %s', category, date, todo_keyword, headline.title)
      local todo_keyword_pos = string.format('%s%s%s', category, date, todo_padding):len()
      if #headline.tags > 0 then
        line = string.format('%-99s %s', line, headline:tags_to_string())
      end

      local item_highlights = {}
      if #agenda_item.highlights then
        item_highlights = vim.tbl_map(function(hl)
          hl.range = Range:new({
            start_line = #content + 1,
            end_line = #content + 1,
            start_col = 1,
            end_col = 0,
          })
          if hl.todo_keyword then
            hl.range.start_col = todo_keyword_pos + 1
            hl.range.end_col = todo_keyword_pos + hl.todo_keyword:len() + 1
          end
          return hl
        end, agenda_item.highlights)
      end

      if headline:is_clocked_in() then
        table.insert(item_highlights, {
          range = Range:new({
            start_line = #content + 1,
            end_line = #content + 1,
            start_col = 1,
            end_col = 0,
          }),
          hl_group = 'Visual',
          whole_line = true,
        })
      end

      table.insert(content, {
        line_content = line,
        line = #content,
        jumpable = true,
        file = headline.file,
        file_position = headline.range.start_line,
        highlights = item_highlights,
        agenda_item = agenda_item,
        headline = headline,
      })
    end
  end

  self.content = content
  self.highlights = highlights
  self.active_view = 'agenda'
  if self.show_clock_report then
    self.clock_report = ClockReport.from_date_range(self.from, self.to)
    utils.concat(self.content, self.clock_report:draw_for_agenda(#self.content + 1))
  end
  return self
end

function AgendaView:_format_day(day)
  return string.format('%-10s %s', day:format('%A'), day:format('%d %B %Y'))
end

return AgendaView
