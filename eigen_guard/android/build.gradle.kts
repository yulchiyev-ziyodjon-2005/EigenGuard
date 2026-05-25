allprojects {
    repositories {
        // Aliyun mirror — birinchi navbatda (Maven Central handshake issue uchun)
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        // Tencent fallback
        maven { url = uri("https://mirrors.cloud.tencent.com/nexus/repository/maven-public/") }
        // Original repolar
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// flutter_vision va boshqa eski paketlar uchun namespace patch
subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
        if (android.namespace.isNullOrEmpty()) {
            android.namespace = project.group.toString().ifEmpty {
                "com.example.${project.name.replace("-", "_")}"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
