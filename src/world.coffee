ChunkArray = Uint8Array || Array

CUBE_SIZE = 1.0
CHUNK_SIZE = 16
TEXTURES_PER_ROW = 16
BLOCK_TYPES =
  air:          0
  grass:        1
  stone:        2
  dirt:         3


makeNewChunk = ->
  new ChunkArray CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE


div = (x, y) -> parseInt x / y
mod = (x, y) -> (x % y + y) % y


class World
  constructor: ->
    @chunks = {}
    @cachedVBOs = {}
    @dirtyVBOs = {}
    @atlas = webglmc.resmgr.resources.terrain
    @shader = webglmc.resmgr.resources.simpleShader
    @blockTextures = {}

  getBlockTexture: (blockType) ->
    rv = @blockTextures[blockType]
    if rv?
      return rv

    index = blockType - 1
    totalWidth = @atlas.width
    sliceSize = totalWidth / TEXTURES_PER_ROW

    x = (index % TEXTURES_PER_ROW) * sliceSize
    y = (TEXTURES_PER_ROW - (parseInt index / TEXTURES_PER_ROW) - 1) * sliceSize
    @blockTextures[blockType] = @atlas.slice x, y, sliceSize, sliceSize

  getBlock: (x, y, z) ->
    cx = div x, CHUNK_SIZE
    cy = div y, CHUNK_SIZE
    cz = div z, CHUNK_SIZE
    chunk = this.getChunk cx, cy, cz
    if !chunk?
      return 0
    inX = mod x, CHUNK_SIZE
    inY = mod y, CHUNK_SIZE
    inZ = mod z, CHUNK_SIZE
    rv = chunk[inX + inY * CHUNK_SIZE + inZ * CHUNK_SIZE * CHUNK_SIZE]
    rv

  setBlock: (x, y, z, type) ->
    cx = div x, CHUNK_SIZE
    cy = div y, CHUNK_SIZE
    cz = div z, CHUNK_SIZE
    chunk = this.getChunk cx, cy, cz, true
    inX = mod x, CHUNK_SIZE
    inY = mod y, CHUNK_SIZE
    inZ = mod z, CHUNK_SIZE
    oldType = chunk[x + y * CHUNK_SIZE + z * CHUNK_SIZE * CHUNK_SIZE]
    chunk[x + y * CHUNK_SIZE + z * CHUNK_SIZE * CHUNK_SIZE] = type

    this.markVBODirty cx, cy, cz

    # in case we replace air with non air at an edge block we need
    # to mark the vbos nearly as dirty
    if ((type == 0) != (oldType == 0))
      if (mod(x + 1, CHUNK_SIZE) == 0) then this.markVBODirty cx + 1, cy, cz
      if (mod(x - 1, CHUNK_SIZE) == 0) then this.markVBODirty cx - 1, cy, cz
      if (mod(y + 1, CHUNK_SIZE) == 0) then this.markVBODirty cx, cy + 1, cz
      if (mod(y - 1, CHUNK_SIZE) == 0) then this.markVBODirty cx, cy - 1, cz
      if (mod(z + 1, CHUNK_SIZE) == 0) then this.markVBODirty cx, cy, cz + 1
      if (mod(z - 1, CHUNK_SIZE) == 0) then this.markVBODirty cx, cy, cz - 1

  getChunk: (x, y, z, create = false) ->
    key = "#{x}|#{y}|#{z}"
    chunk = @chunks[key]
    if !chunk? && create
      @chunks[key] = chunk = makeNewChunk()
    chunk

  updateVBO: (x, y, z) ->
    chunk = this.getChunk x, y, z
    if !chunk
      return null
    maker = new webglmc.CubeMaker CUBE_SIZE

    offX = x * CHUNK_SIZE
    offY = y * CHUNK_SIZE
    offZ = z * CHUNK_SIZE

    isAir = (cx, cy, cz) =>
      if cx >= 0 && cy >= 0 && cz >= 0 &&
         cx < CHUNK_SIZE && cy < CHUNK_SIZE && cz < CHUNK_SIZE
        return chunk[cx + cy * CHUNK_SIZE + cz * CHUNK_SIZE * CHUNK_SIZE] == 0
      return this.getBlock(offX + cx, offY + cy, offZ + cz) == 0
      
    addSide = (side, type) =>
      texture = this.getBlockTexture type
      maker.addSide side, cx * CUBE_SIZE, cy * CUBE_SIZE, cz * CUBE_SIZE, texture

    for cz in [0...CHUNK_SIZE]
      for cy in [0...CHUNK_SIZE]
        for cx in [0...CHUNK_SIZE]
          block = chunk[cx + cy * CHUNK_SIZE + cz * CHUNK_SIZE * CHUNK_SIZE]
          if block == 0
            continue
          if isAir(cx - 1, cy, cz) then addSide('left', block)
          if isAir(cx + 1, cy, cz) then addSide('right', block)
          if isAir(cx, cy - 1, cz) then addSide('bottom', block)
          if isAir(cx, cy + 1, cz) then addSide('top', block)
          if isAir(cx, cy, cz - 1) then addSide('far', block)
          if isAir(cx, cy, cz + 1) then addSide('near', block)

    if maker.vertexCount > 0
      maker.makeVBO()

  markVBODirty: (x, y, z) ->
    @dirtyVBOs["#{x}|#{y}|#{z}"] = true

  getChunkVBO: (x, y, z) ->
    key = "#{x}|#{y}|#{z}"
    chunk = @chunks[key]
    if !chunk
      return null
    vbo = @cachedVBOs[key]
    if @dirtyVBOs[key] || !vbo?
      if vbo?
        vbo.destroy()
      vbo = this.updateVBO x, y, z
      delete @dirtyVBOs[key]
      if vbo
        @cachedVBOs[key] = vbo
    vbo

  getChunkVBOByKey: (key) ->
    [x, y, z] = key.split('|')
    this.getChunkVBO(+x, +y, +z)

  draw: ->
    @shader.use()
    @atlas.bind()
    for key, chunk of @chunks
      vbo = this.getChunkVBOByKey(key)
      if vbo
        vbo.draw()


public = window.webglmc ?= {}
public.World = World
public.BLOCK_TYPES = BLOCK_TYPES