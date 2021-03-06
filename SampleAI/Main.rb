# require "pry"
require 'matrix'
require 'complex'


class Player
  attr_reader :map

  def initialize souls, map, skill_count
    @souls = souls
    @map   = map
    @skill_count = skill_count
  end
end

class Map
  attr_reader :row, :col, :cells, :ninjas, :items, :enemies

  class Cell
    attr_reader :state, :point, :effective, :item_effective, :enemies_effective
    def initialize x, y, state
      @point = Point.new(x, y)
      @state = state
      @effective = has_object? ? -1 : 0 #障害物ありの場合は影響マップを0で初期化
    end
    def has_object?
      self.state == "W" || self.state == "O"
    end
    def x
      @point.x
    end
    def y
      @point.y
    end
  end

  def initialize row, col, cells, ninjas, enemies, items
    @row = row
    @col = col
    @cells = Array.new(@row){ Array.new(@col) }

    cells.each_with_index do |rows, x|
      rows.each_with_index do |state, y|
        @cells[x][y] = Cell.new(x, y, state)
      end
    end

    @ninjas  = ninjas
    @enemies = enemies
    @items   = items
  end

  def nearest_item x, y
    distances = self.items.map{|i| Math.sqrt((i.x - x).abs**2 + (i.y - y).abs**2) }
    idx = distances.index(distances.min)
    return self.items[idx]
  end

  def movable? point
    !self.cells[point.x][point.y].has_object?
  end

  def distance_evaluate start_point, reverse_flag
    distance_map = Array.new(self.row) { Array.new(self.col, nil)}
    distance_map.each_with_index do |row, x|
      row.each_with_index do |cell, y|
        distance_map[x][y] = -1 if self.cells[x][y].has_object?
      end
    end
    distance_map[start_point.x][start_point.y] = 0
    que = [start_point]
    max_num = 0
    while que.size > 0
      now_point = que.shift
      [now_point.left, now_point.right, now_point.up, now_point.down].each do |po|
        if distance_map[po.x][po.y] == nil && distance_map[po.x][po.y] != -1 && po.x > 0 && po.y > 0
          distance_map[po.x][po.y] = distance_map[now_point.x][now_point.y] + 1
          que << po
          max_num = distance_map[po.x][po.y]
        end
      end
    end
    max_num *= 1.0
    if reverse_flag
      return distance_map.map { |e1| e1.map { |e2| e2 < 0 ? -1 : (max_num - e2)/max_num}  }
    else
      return distance_map.map { |e1| e1.map { |e2| e2/max_num  }  }
    end
  end
end


class Point
  attr_reader :x, :y, :left, :right, :up, :down
  def initialize x, y
    @x = x
    @y = y
  end
  def left
    @left ||= Point.new(x, y+1)
  end
  def right
    @right ||= Point.new(x, y-1)
  end
  def up
    @up ||= Point.new(x+1, y)
  end
  def down
    @down ||= Point.new(x-1, y)
  end
end

class Character
  attr_reader :id, :point
  def initialize id, x, y
    @id = id
    @point = Point.new(x, y)
  end
  def x
    @point.x
  end
  def y
    @point.y
  end
end

class Item
  attr_reader :x, :y, :point

  def initialize x, y
    @x = x
    @y = y
    @point = Point.new(x, y)
  end
  def x
    @point.x
  end
  def y
    @point.y
  end
end

class Skill
  def initialize id, cost
    @id   = id
    @cost = cost
  end
end

class AI
  def initialize name
    @name = name
  end

  def think
    puts @name
    $stdout.flush

    while true
      # 制限時間
      @timelimit = $stdin.gets.strip

      # スキルの吸い出し
      skill_num = $stdin.gets.strip
      skill_costs = $stdin.gets.strip.split(" ").map{|cost| cost.to_i}
      @skills = []
      skill_costs.each_with_index do |cost, id|
        @skills.push Skill.new id, cost
      end

      # 各プレイヤーの情報
      # 順番に注意！（inputは自分、相手の順に情報が入ってくる）
      @me    = extract_player $stdin
      @rival = extract_player $stdin
      # スキルは使わないので2固定
      puts "2"

      # 忍者の行動決定
      #enemyから遠いほど値を大きくしたい
      evaluate_enemy_map = Matrix.rows(Array.new(@me.map.row) { Array.new(@me.map.col, 0) } )
      @me.map.enemies.each do |enemy|
        evaluate_enemy_map += Matrix.rows(@me.map.distance_evaluate enemy.point, false)
      end
      #正規化

      # evaluate_enemy_map = Matrix.rows evaluate_enemy_map.to_a.map{|a1| a1.map{|a2| a2 < 0 ? -1.0 : a2 }}

      #itemから近いほど値大きい
      evaluate_item_map = Matrix.rows(Array.new(@me.map.row) { Array.new(@me.map.col, 0) } )
      @me.map.items.each do |item|
        evaluate_item_map += Matrix.rows(@me.map.distance_evaluate item.point, true)
      end
      evaluate_item_map = evaluate_item_map * 1.0 / @me.map.items.count unless @me.map.items.count == 0
      # evaluate_item_map = Matrix.rows evaluate_item_map.to_a.map{|a1| a1.map{|a2| a2 > 0 ? -1.0 : 1.0 - a2}}

      effective_map = evaluate_enemy_map * 0.5 + evaluate_item_map * 0.5

      effective_map = effective_map.to_a

      @me.map.ninjas.each do |ninja|
        now_point = ninja.point
        steps = []
        step_num = 0
        next_step = ""
        next_point = now_point
        while step_num < 2
          max = -1
          [[now_point.right, "R"], [now_point.left, "L"], [now_point.down, "D"], [now_point.up, "U"]].each do |po, code|
            if po.x >= 0 && po.y >= 0 && po.x <= @me.map.row && po.y <= @me.map.col && !@me.map.cells[po.x][po.y].has_object? && effective_map[po.x][po.y] > max
              next_step = code
              next_point = po
              max = effective_map[po.x][po.y]
            end
          end
          steps << next_step
          now_point = next_point
          step_num += 1
        end
        puts steps[0,2].join("")
      end
      $stdout.flush
    end
  end

  def extract_player file
    # スキルを使えるポイント情報を吸い上げる
    souls = file.gets.strip

    # mapの情報を吸い上げる
    size = file.gets.split(" ")
    row = size[0].to_i
    col = size[1].to_i
    cells = Array.new(row){ Array.new(col) }
    row.times do |x|
      line = file.gets.strip.split("")
      line.each_with_index do |state, y|
        cells[x][y] = state
      end
    end

    # ユニットの情報を吸い上げる
    ninjas  = extract_character file
    enemies = extract_character file
    items   = extract_item file

    # スキル使用回数を吸い上げる
    skill_count = file.gets.split(" ")

    map    = Map.new(row, col, cells, ninjas, enemies, items)
    player = Player.new(souls, map, skill_count)

    return player
  end

  def extract_character file
    tmp = []
    num = file.gets.strip.to_i
    num.times do |i|
      chars = file.gets.strip.split(" ")
      tmp.push Character.new(chars[0].to_i, chars[1].to_i, chars[2].to_i)
    end
    return tmp
  end

  def extract_item file
    tmp = []
    num = file.gets.strip.to_i
    num.times do |i|
      chars = file.gets.strip.split(" ")
      tmp.push Item.new(chars[0].to_i, chars[1].to_i)
    end
    return tmp
  end
end

# AI起動
ai = AI.new "mu-mu-AI.rb"
ai.think

