# Rendering size of a single block cube
CUBE_SIZE = 1.0

# must be a power of two for the octree based fast raycasting
# to work properly.
CHUNK_SIZE = 32

# View distances are in chunks
VIEW_DISTANCE_X = 2
VIEW_DISTANCE_Y = 2
VIEW_DISTANCE_Z = 2

# Currently blocks are one byte in size which limits them to 255
# different block types.
BLOCK_TYPES =
  air:          0
  grass01:      1
  grass02:      2
  grass03:      3
  grass04:      4
  stone:        10
  granite:      11
  rock01:       20
  rock02:       21
  water:        30
  sand:         31


ChunkArray = Uint8Array

parseKey = (key) ->
  [x, y, z] = key.split('|')
  [+x, +y, +z]

div = (x, y) ->
  Math.floor x / y

mod = (x, y) ->
  (x % y + y) % y

makeBlockAtlas = ->
  builder = new webglmc.AtlasBuilder 1024, 1024, gridAdd: true
  for key, blockID of BLOCK_TYPES
    if blockID == 0
      continue
    img = webglmc.resmgr.resources["blocks/#{key}"]
    builder.add blockID, img
  builder.makeAtlas mipmaps: true

makeNewChunk = (chunkSize) ->

forceChunkType = (chunk) ->
  if !chunk instanceof ChunkArray
    chunk = new ChunkArray chunk
  chunk


class WorldRaycastResult
  constructor: (ray, hit, x, y, z, blockID) ->
    @x = x
    @y = y
    @z = z
    @blockID = blockID
    @ray = ray
    @hit = hit


class World
  constructor: (seed = null) ->
    if seed == null
      seed = parseInt Math.random() * 10000000
    @seed = seed
    @generator = new webglmc.WorldGenerator this
    @chunkSize = CHUNK_SIZE
    @chunks = {}
    @cachedVBOs = {}
    @dirtyVBOs = {}
    @shader = webglmc.resmgr.resources['shaders/simple']
    @sunDirection = vec3.create([0.7, 0.8, 1.0])
    @frustumCulling = webglmc.getRuntimeParameter('frustumCulling') == '1'

    @displays =
      chunkStats: webglmc.debugPanel.addDisplay 'Chunk stats'

    @atlas = makeBlockAtlas()

  getBlockTexture: (blockID) ->
    @atlas.slices[blockID]

  getBlock: (x, y, z) ->
    cx = div x, @chunkSize
    cy = div y, @chunkSize
    cz = div z, @chunkSize
    chunk = this.getChunk cx, cy, cz
    if !chunk?
      return 0
    inX = mod x, @chunkSize
    inY = mod y, @chunkSize
    inZ = mod z, @chunkSize
    chunk[inX + inY * @chunkSize + inZ * @chunkSize * @chunkSize]

  setBlock: (x, y, z, type) ->
    cx = div x, @chunkSize
    cy = div y, @chunkSize
    cz = div z, @chunkSize
    chunk = this.getChunk cx, cy, cz, true
    inX = mod x, @chunkSize
    inY = mod y, @chunkSize
    inZ = mod z, @chunkSize
    oldType = chunk[inX + inY * @chunkSize + inZ * @chunkSize * @chunkSize]
    chunk[inX + inY * @chunkSize + inZ * @chunkSize * @chunkSize] = type

    this.markVBODirty cx, cy, cz

    # in case we replace air with non air at an edge block we need
    # to mark the vbos nearly as dirty
    if ((type == 0) != (oldType == 0))
      if (mod(x + 1, @chunkSize) == 0) then this.markVBODirty cx + 1, cy, cz
      if (mod(x - 1, @chunkSize) == 0) then this.markVBODirty cx - 1, cy, cz
      if (mod(y + 1, @chunkSize) == 0) then this.markVBODirty cx, cy + 1, cz
      if (mod(y - 1, @chunkSize) == 0) then this.markVBODirty cx, cy - 1, cz
      if (mod(z + 1, @chunkSize) == 0) then this.markVBODirty cx, cy, cz + 1
      if (mod(z - 1, @chunkSize) == 0) then this.markVBODirty cx, cy, cz - 1

  getChunk: (x, y, z, create = false) ->
    key = "#{x}|#{y}|#{z}"
    chunk = @chunks[key]
    if !chunk? && create
      @chunks[key] = chunk = new ChunkArray @chunkSize * @chunkSize * @chunkSize
    chunk

  setChunk: (x, y, z, chunk) ->
    key = "#{x}|#{y}|#{z}"
    @chunks[key] = forceChunkType chunk
    @dirtyVBOs[key] = true
    this.markVBODirty x + 1, y, z
    this.markVBODirty x - 1, y, z
    this.markVBODirty x, y + 1, z
    this.markVBODirty x, y - 1, z
    this.markVBODirty x, y, z + 1
    this.markVBODirty x, y, z - 1

  updateVBO: (x, y, z) ->
    chunk = this.getChunk x, y, z
    if !chunk
      return null
    maker = new webglmc.CubeMaker CUBE_SIZE

    offX = x * @chunkSize
    offY = y * @chunkSize
    offZ = z * @chunkSize

    isAir = (cx, cy, cz) =>
      if cx >= 0 && cy >= 0 && cz >= 0 &&
         cx < @chunkSize && cy < @chunkSize && cz < @chunkSize
        return chunk[cx + cy * @chunkSize + cz * @chunkSize * @chunkSize] == 0
      return this.getBlock(offX + cx, offY + cy, offZ + cz) == 0
      
    addSide = (side) =>
      texture = this.getBlockTexture blockID
      maker.addSide side, offX + cx * CUBE_SIZE, offY + cy * CUBE_SIZE,
        offZ + cz * CUBE_SIZE, texture

    for cz in [0...@chunkSize]
      for cy in [0...@chunkSize]
        for cx in [0...@chunkSize]
          blockID = chunk[cx + cy * @chunkSize + cz * @chunkSize * @chunkSize]
          if blockID == 0
            continue
          if isAir cx - 1, cy, cz then addSide 'left'
          if isAir cx + 1, cy, cz then addSide 'right'
          if isAir cx, cy - 1, cz then addSide 'bottom'
          if isAir cx, cy + 1, cz then addSide 'top'
          if isAir cx, cy, cz - 1 then addSide 'far'
          if isAir cx, cy, cz + 1 then addSide 'near'

    maker.makeVBO()

  markVBODirty: (x, y, z) ->
    key = "#{x}|#{y}|#{z}"
    if @cachedVBOs[key]
      @dirtyVBOs[key] = true

  getChunkVBO: (x, y, z) ->
    key = "#{x}|#{y}|#{z}"
    chunk = @chunks[key]
    if !chunk
      return null
    vbo = @cachedVBOs[key]
    if !vbo || @dirtyVBOs[key]
      if vbo
        vbo.destroy()
      vbo = this.updateVBO x, y, z
      delete @dirtyVBOs[key]
      if vbo
        @cachedVBOs[key] = vbo
    vbo

  iterVisibleVBOs: (callback) ->
    start = Date.now()
    frustum = webglmc.engine.getCurrentFrustum()
    cameraPos = webglmc.engine.getCameraPos()
    chunkCount = 0
    rv = []
    aabb = new webglmc.AABB()
    chunkSize = CUBE_SIZE * @chunkSize

    for key, chunk of @chunks
      chunkCount++
      [x, y, z] = parseKey key
      vbo = this.getChunkVBO x, y, z
      if !vbo
        continue

      # For some reason the frustum culling is broken so I just cull against
      # larger objects.  Seems to do the trick.
      aabb.vec1[0] = chunkSize * (x - 1)
      aabb.vec1[1] = chunkSize * (y - 1)
      aabb.vec1[2] = chunkSize * (z - 1)
      vec3.add aabb.vec1, [chunkSize * 3, chunkSize * 3, chunkSize * 3], aabb.vec2
      distance = vec3.subtract aabb.vec1, cameraPos

      if !@frustumCulling || frustum.testAABB(aabb) >= 0
        rv.push vbo: vbo, distance: vec3.norm2(distance)

    rv.sort (a, b) -> a.distance - b.distance
    dt = (Date.now() - start) / 1000
    @displays.chunkStats.setText "chunks=#{chunkCount} visibleVBOs=#{
        rv.length} chunkUpdate=#{dt}ms"

    for info in rv
      callback info.vbo

  chunkAtCameraPosition: ->
    [x, y, z] = webglmc.engine.getCameraPos()
    [Math.floor(x / CUBE_SIZE / @chunkSize + 0.5),
     Math.floor(y / CUBE_SIZE / @chunkSize + 0.5),
     Math.floor(z / CUBE_SIZE / @chunkSize + 0.5)]

  requestMissingChunks: ->
    [x, y, z] = this.chunkAtCameraPosition()
    for cx in [x - VIEW_DISTANCE_X..x + VIEW_DISTANCE_X]
      for cy in [y - VIEW_DISTANCE_Y..y + VIEW_DISTANCE_Y]
        for cz in [z - VIEW_DISTANCE_Z..z + VIEW_DISTANCE_Z]
          chunk = this.getChunk cx, cy, cz
          if !chunk
            this.requestChunk cx, cy, cz

  requestChunk: (x, y, z) ->
    # ensure chunk exists so that we don't request chunks
    # multiple times in requestMissingChunks
    this.getChunk x, y, z, true
    @generator.generateChunk x, y, z

  iterChunksAroundCamera: (range, callback) ->
    if range == null
      for key, chunk of @chunks
        callback(chunk, parseKey(key)...)
      return

    [cx, cy, cz] = this.chunkAtCameraPosition()
    for x in [cx - range..cx + range]
      for y in [cy - range..cy + range]
        for z in [cz - range..cz + range]
          chunk = @chunks["#{x}|#{y}|#{z}"]
          if chunk
            callback(chunk, x, y, z)

  fastChunkRaycast: (chunk, cx, cy, cz, ray, callback) ->
    aabb = new webglmc.AABB()
    offX = @chunkSize * cx
    offY = @chunkSize * cy
    offZ = @chunkSize * cz

    walk = (inX, inY, inZ, inSize) =>
      realX = offX + inX
      realY = offY + inY
      realZ = offZ + inZ
      actualInSize = CUBE_SIZE * inSize

      aabb.vec1[0] = realX * CUBE_SIZE
      aabb.vec1[1] = realY * CUBE_SIZE
      aabb.vec1[2] = realZ * CUBE_SIZE
      aabb.vec2[0] = aabb.vec1[0] + actualInSize
      aabb.vec2[1] = aabb.vec1[1] + actualInSize
      aabb.vec2[2] = aabb.vec1[2] + actualInSize

      hit = ray.intersectsAABB aabb
      if !hit
        return

      if inSize == 1
        blockID = chunk[inX + inY * @chunkSize + inZ * @chunkSize * @chunkSize]
        if blockID
          callback new WorldRaycastResult ray, hit, realX, realY, realZ, blockID
        return

      newInSize = inSize / 2
      walk inX, inY, inZ, newInSize
      walk inX + newInSize, inY, inZ, newInSize
      walk inX, inY + newInSize, inZ, newInSize
      walk inX, inY, inZ + newInSize, newInSize
      walk inX + newInSize, inY + newInSize, inZ, newInSize
      walk inX, inY + newInSize, inZ + newInSize, newInSize
      walk inX + newInSize, inY, inZ + newInSize, newInSize
      walk inX + newInSize, inY + newInSize, inZ + newInSize, newInSize

    walk 0, 0, 0, @chunkSize

  performRayCast: (ray, range = null) ->
    aabb = new webglmc.AABB()
    chunkSize = CUBE_SIZE * @chunkSize
    bestResult = null

    this.iterChunksAroundCamera range, (chunk, cx, cy, cz) =>
      aabb.vec1[0] = chunkSize * cx
      aabb.vec1[1] = chunkSize * cy
      aabb.vec1[2] = chunkSize * cz
      aabb.vec2[0] = aabb.vec1[0] + chunkSize
      aabb.vec2[1] = aabb.vec1[1] + chunkSize
      aabb.vec2[2] = aabb.vec1[2] + chunkSize
      if !ray.intersectsAABB aabb
        return

      this.fastChunkRaycast chunk, cx, cy, cz, ray, (result) ->
        if !bestResult || bestResult.hit.distance > result.hit.distance
          bestResult = result

    bestResult

  pickBlockAtScreenPosition: (x, y, range = null) ->
    ray = webglmc.Ray.fromScreenSpaceNearToFar x, y
    this.performRayCast ray, range

  pickBlockAtScreenCenter: (range = null) ->
    {width, height} = webglmc.engine
    this.pickBlockAtScreenPosition width / 2, height / 2, range

  pickCloseBlockAtScreenCenter: ->
    rv = this.pickBlockAtScreenCenter 1
    if rv && rv.hit.distance < 10 then rv else null

  draw: ->
    {gl} = webglmc.engine

    @shader.use()
    loc = @shader.getUniformLocation "uSunDirection"
    gl.uniform3fv loc, @sunDirection

    @atlas.texture.bind()
    this.iterVisibleVBOs (vbo) =>
      vbo.draw()


public = self.webglmc ?= {}
public.World = World
public.BLOCK_TYPES = BLOCK_TYPES
