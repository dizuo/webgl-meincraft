CUBE_INDEXES = [0, 1, 2, 0, 2, 3]
CUBE_VERTICES =
  near:
    positions: [
      [-1.0, -1.0,  1.0]
      [ 1.0, -1.0,  1.0]
      [ 1.0,  1.0,  1.0]
      [-1.0,  1.0,  1.0]
    ]
    texcoords: [
      [0.0,  0.0]
      [1.0,  0.0]
      [1.0,  1.0]
      [0.0,  1.0]
    ]
  far:
    positions: [
      [-1.0, -1.0, -1.0]
      [-1.0,  1.0, -1.0]
      [ 1.0,  1.0, -1.0]
      [ 1.0, -1.0, -1.0]
    ]
    texcoords: [
      [0.0,  0.0]
      [1.0,  0.0]
      [1.0,  1.0]
      [0.0,  1.0]
    ]
  top:
    positions: [
      [-1.0,  1.0, -1.0]
      [-1.0,  1.0,  1.0]
      [ 1.0,  1.0,  1.0]
      [ 1.0,  1.0, -1.0]
    ]
    texcoords: [
      [0.0,  0.0]
      [1.0,  0.0]
      [1.0,  1.0]
      [0.0,  1.0]
    ]
  bottom:
    positions: [
      [-1.0, -1.0, -1.0]
      [ 1.0, -1.0, -1.0]
      [ 1.0, -1.0,  1.0]
      [-1.0, -1.0,  1.0]
    ]
    texcoords: [
      [0.0,  0.0]
      [1.0,  0.0]
      [1.0,  1.0]
      [0.0,  1.0]
    ]
  right:
    positions: [
      [ 1.0, -1.0, -1.0]
      [ 1.0,  1.0, -1.0]
      [ 1.0,  1.0,  1.0]
      [ 1.0, -1.0,  1.0]
    ]
    texcoords: [
      [0.0,  0.0]
      [1.0,  0.0]
      [1.0,  1.0]
      [0.0,  1.0]
    ]
  left:
    positions: [
      [-1.0, -1.0, -1.0]
      [-1.0, -1.0,  1.0]
      [-1.0,  1.0,  1.0]
      [-1.0,  1.0, -1.0]
    ]
    texcoords: [
      [0.0,  0.0]
      [1.0,  0.0]
      [1.0,  1.0]
      [0.0,  1.0]
    ]


class CubeMaker
  constructor: (defaultSize = 1) ->
    @defaultSize = defaultSize
    @vertexCount = 0
    @positions = []
    @texcoords = []
    @indexes = []

  addSide: (side, x, y, z, texture = null, size = @defaultSize) ->
    halfsize = size / 2
    start = @vertexCount

    for [cx, cy, cz] in CUBE_VERTICES[side].positions
      @positions.push x + (cx * halfsize)
      @positions.push y + (cy * halfsize)
      @positions.push z + (cz * halfsize)

    if texture?
      facX = texture.width / texture.storedWidth
      facY = texture.height / texture.storedHeight
      offX = texture.offsetX / texture.storedWidth
      offY = texture.offsetY / texture.storedHeight

      for [tx, ty] in CUBE_VERTICES[side].texcoords
        @texcoords.push tx * facX + offX
        @texcoords.push ty * facY + offY

    for index in CUBE_INDEXES
      @indexes.push start + index

    @vertexCount += 4

  makeVBO: (upload = true) ->
    vbo = new webglmc.VertexBufferObject 'TRIANGLES', @indexes.length
    vbo.addBuffer 'aVertexPosition', 3, @positions
    vbo.addBuffer 'aTextureCoord', 2, @texcoords
    vbo.addIndexBuffer @indexes
    console.log this
    if upload
      vbo.upload()
    vbo


public = window.webglmc ?= {}
public.CubeMaker = CubeMaker