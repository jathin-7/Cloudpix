import java.io.File

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Keep Gradle intermediates outside OneDrive-synced folders on Windows to
// reduce file lock/delete failures during clean/assemble tasks.
val configuredBuildRoot = providers.gradleProperty("cloudpix.buildRoot").orNull
val defaultBuildRoot = File(
    System.getenv("LOCALAPPDATA") ?: System.getProperty("java.io.tmpdir"),
    "cloudpix-build"
)
val buildRoot = configuredBuildRoot?.let(::File) ?: defaultBuildRoot

rootProject.layout.buildDirectory.set(buildRoot)

subprojects {
    val newSubprojectBuildDir = File(buildRoot, project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
