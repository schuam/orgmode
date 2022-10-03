local helpers = require('tests.plenary.ui.helpers')

describe('Tables', function()
  after_each(function()
    vim.cmd([[silent! %bw!]])
  end)

  it('should generate basic table structure from pipe or hr line', function()
    helpers.load_file_content({
      '|',
    })
    vim.fn.cursor({ 1, 1 })
    vim.cmd([[norm gqgq]])
    assert.are.same({ '|  |' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

    helpers.load_file_content({
      '|-',
    })

    vim.cmd([[norm gqgq]])
    assert.are.same({ '|--|' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('should format the table', function()
    helpers.load_file_content({
      '  |head1 |  ',
      '  |-  ',
      '  |content|  ',
    })
    vim.fn.cursor({ 2, 1 })
    vim.cmd([[norm! gqgq]])

    assert.are.same({
      '  | head1   |',
      '  |---------|',
      '  | content |',
    }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('should format multi column table', function()
    helpers.load_file_content({
      '|first|second|',
      '|-',
      '|third cell| fourth cell|',
      '|fifth|sixth| seventh',
    })
    vim.fn.cursor({ 1, 1 })
    vim.cmd([[norm gqgq]])
    assert.are.same({
      '| first      | second      |         |',
      '|------------+-------------+---------|',
      '| third cell | fourth cell |         |',
      '| fifth      | sixth       | seventh |',
    }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('should add new row on enter', function()
    helpers.load_file_content({
      '| test |',
    })
    vim.fn.cursor({ 1, 6 })
    vim.cmd([[exe "norm a\<CR>"]])
    assert.are.same({
      '| test |',
      '|      |',
    }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

    helpers.load_file_content({
      '| test | col |',
      '|      | value',
    })
    vim.fn.cursor({ 2, 13 })
    vim.cmd([[exe "norm a\<CR>"]])
    assert.are.same({
      '| test | col   |',
      '|      | value |',
      '|      |       |',
    }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('should add new row on enter in list item', function()
    helpers.load_file_content({
      '* TODO Test',
      '  DEADLINE: <2021-07-21 Wed 22:02>',
      '  - Some list item',
      '    | test |',
    })
    vim.fn.cursor({ 4, 10 })
    vim.cmd([[exe "norm a\<CR>"]])
    assert.are.same({
      '* TODO Test',
      '  DEADLINE: <2021-07-21 Wed 22:02>',
      '  - Some list item',
      '    | test |',
      '    |      |',
    }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)
end)
