import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Older Android plugins still rely on the manifest package instead of AGP's namespace.
    val legacyNamespaces = mapOf(
        "google_mlkit_commons" to "com.google_mlkit_commons",
        "google_mlkit_text_recognition" to "com.google_mlkit_text_recognition",
    )
    legacyNamespaces[project.name]?.let { legacyNamespace ->
        pluginManager.withPlugin("com.android.library") {
            extensions.configure<LibraryExtension> {
                namespace = legacyNamespace
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
