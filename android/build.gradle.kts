import groovy.json.JsonSlurper
import java.net.URI

allprojects {
    repositories {
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

val patchFlutterSoloud by tasks.registering {
    doLast {
        val packageConfig = rootProject.file("../.dart_tool/package_config.json")
        check(packageConfig.isFile) { "Run flutter pub get before building Android." }
        val packages = (JsonSlurper().parse(packageConfig) as Map<*, *>)["packages"] as List<*>
        val soloud = packages.map { it as Map<*, *> }.single { it["name"] == "flutter_soloud" }
        val packageRoot = File(URI(soloud["rootUri"].toString()))
        val manifest = File(packageRoot, "pubspec.yaml").readText()
        check(Regex("(?m)^version:\\s*3\\.5\\.4\\s*$").containsMatchIn(manifest)) {
            "Expected flutter_soloud 3.5.4 at $packageRoot"
        }
        val player = File(packageRoot, "src/player.cpp")
        val source = player.readText()
        val flag = "SoLoud::Soloud::CLIP_ROUNDOFF,"
        val initWithoutClipper = Regex("soloud\\.init\\([\\r\\n\\t ]*0,")
        when {
            source.windowed(flag.length).count { it == flag } == 1 -> player.writeText(source.replace(flag, "0,"))
            initWithoutClipper.containsMatchIn(source) -> Unit
            else -> error("Unexpected flutter_soloud 3.5.4 Player::init source; refusing an unsafe patch")
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

gradle.projectsEvaluated {
    allprojects {
        tasks.configureEach {
            if (name.startsWith("externalNativeBuild") || name.startsWith("configureCMake")) {
                dependsOn(patchFlutterSoloud)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
