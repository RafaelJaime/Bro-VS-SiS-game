export class PlayerObject {
  constructor(name, color, image, prefix, suffix, enabled = true) {
    this.name = name
    this.color = color
    this.image = image
    this.prefix = prefix
    this.suffix = suffix
    this.defaultImage = prefix + '014' + suffix
    this.enabled = enabled
  }
}
