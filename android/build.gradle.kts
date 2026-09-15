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

// Sessão 2026-05-24 (exec5) — Alinha JVM 17 em TODOS os plugins ANTES do
// evaluationDependsOn (que força evaluation imediata e impede afterEvaluate).
//
// Razão: o Flutter agora usa JDK 17 (flutter config --jdk-dir) MAS plugins
// como audioplayers_android herdam Java 1.8 default + Kotlin 17, e
// connectycube_flutter_call_kit traz Kotlin 21 — AGP detecta mismatch e
// recusa compilar com "Inconsistent JVM Target Compatibility".
//
// Estratégia cirúrgica (NÃO repetir o erro de exec4):
//   • Kotlin: configureEach na task (funciona já, jvmTarget=17)
//   • Java: extensions BaseExtension.compileOptions DENTRO de afterEvaluate
//     (espera plugin terminar configuração; aplicar fora do afterEvaluate
//     dá "sourceCompatibility has been finalized")
//
// NÃO usar JavaCompile.targetCompatibility global (exec4 P4 partiu o
// classpath de flutter_local_notifications — perdeu android.content).
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            (ext as? com.android.build.gradle.BaseExtension)?.apply {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

// evaluationDependsOn DEPOIS do bloco JVM-align acima, para que o callback
// afterEvaluate fique registado ANTES de :app forçar evaluation.
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
