class_name TestAutoWrapper

static func test_version_major():
	var wrapper := OcctlCoreWrapper.new()
	var result = wrapper.version_major()
	if result < 0:
		return "version_major should return a non-negative value, got: %d" % result
	return ""

static func test_version_minor():
	var wrapper := OcctlCoreWrapper.new()
	var result = wrapper.version_minor()
	if result < 0:
		return "version_minor should return a non-negative value, got: %d" % result
	return ""

static func test_version_patch():
	var wrapper := OcctlCoreWrapper.new()
	var result = wrapper.version_patch()
	if result < 0:
		return "version_patch should return a non-negative value, got: %d" % result
	return ""

