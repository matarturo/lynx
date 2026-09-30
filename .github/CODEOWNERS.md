# CODEOWNERS — https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
#
# Sintaxis: <patrón> <usuario(s)> <email opcional>
# El último patrón que hace match gana.
#
# Como mantenedor único, todo lo revisa @matarturo. Cuando entre un
# colaborador, puedes añadirlo por área (ej. docs, CI) sin tocar esto.

# Por defecto, todo el repo
*                       @matarturo

# Código principal — máxima cautela
/lynx.sh                @matarturo

# Gobernanza y documentación
/README.md              @matarturo
/CONTRIBUTING.md        @matarturo
/SECURITY.md            @matarturo
/CODE_OF_CONDUCT.md     @matarturo
/CHANGELOG.md           @matarturo

# Infraestructura y CI
/.github/               @matarturo

# Licencia y avisos: cambios solo con revisión explícita
/LICENSE                @matarturo
/NOTICE                 @matarturo
