package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

var GA_VERSION = "ga"
var BETA_VERSION = "beta"

var oPath = flag.String("output", "", "path to output generated files to")
var ver = flag.String("version", "", "version name, value must be `ga` or `beta`")

func main() {
	var version string
	var outputPath string

	flag.Parse()
	outputPath = *oPath
	version = *ver
	if outputPath == "" {
		log.Fatalf("missing output flag: provide `--output <path>` to set the path to output generated files to")
	}
	if version == "" {
		log.Fatalf("missing version flag: provide `--version <ga|beta>` to set the path to output generated files to")
	}
	if version != GA_VERSION && version != BETA_VERSION {
		log.Fatalf("invalid version flag value: value must be `%s` or `%s`", GA_VERSION, BETA_VERSION)
	}

	var terraformResourceDirectory string
	switch version {
	case GA_VERSION:
		terraformResourceDirectory = "google"
	case BETA_VERSION:
		terraformResourceDirectory = "google-beta"
	default:
		log.Fatalf("invalid version flag value: value must be `%s` or `%s`", GA_VERSION, BETA_VERSION)
	}

	log.Printf("Generating TeamCity configuration service package map for `%s` provider", terraformResourceDirectory)

	// Get a list of the service packages found in a given directory
	servicesDir := fmt.Sprintf("%s/%s/services", outputPath, terraformResourceDirectory)
	serviceList, err := readAllServicePackages(servicesDir)
	if err != nil {
		log.Fatalf("error determining service package list: %s", err)
	}

	// Create a string of the map that should be created in .teamcity/components/generated/services.kt
	relativeServicesDir := fmt.Sprintf("./%s/services", terraformResourceDirectory)
	serviceMap, err := createMap(serviceList, relativeServicesDir)
	if err != nil {
		log.Fatalf("error creating service package map: %s", err)
	}

	// Ensure .teamcity/components/generated/services.kt exists, create if not present
	// "Create creates or truncates the named file. If the file already exists, it is truncated."
	servicesKtFilePath := fmt.Sprintf("%s/.teamcity/components/generated/services.kt", outputPath)
	log.Printf("Opening %s", servicesKtFilePath)
	f, err := os.Create(servicesKtFilePath)
	if err != nil {
		log.Fatalf("error creating or truncating existing file `.teamcity/components/generated/services.kt` in output directory: %s", err)
	}
	defer f.Close()

	// Save map to .teamcity/components/generated/services.kt
	log.Printf("Saving service map to %s", servicesKtFilePath)
	_, err = f.Write([]byte(serviceMap))
	if err != nil {
		log.Fatalf("error writing to file `.teamcity/components/generated/services.kt` in output directory: %s", err)
	}

	log.Println("Finished")
}

func readAllServicePackages(providerDir string) ([]string, error) {
	packages, err := os.ReadDir(providerDir)
	if err != nil {
		return nil, err
	}
	var services = make([]string, 0)

	for _, p := range packages {
		if p.IsDir() {
			services = append(services, p.Name())
		}
	}
	if len(services) == 0 {
		return nil, fmt.Errorf("found 0 service packages in %s", providerDir)
	}
	return services, nil
}

func createMap(packageNames []string, servicesDir string) (string, error) {

	entryTemplate := `    "%s" to mapOf(
        "name" to "%s",
        "displayName" to "%s",
        "path" to "%s"
    ),
`
	lastEntryTemplate := `    "%s" to mapOf(
        "name" to "%s",
        "displayName" to "%s",
        "path" to "%s"
    )` // No trailing comma
	caser := cases.Title(language.English)

	var b strings.Builder
	// Add copyright header
	b.WriteString("/*\n")
	b.WriteString(" * Copyright (c) HashiCorp, Inc.\n")
	b.WriteString(" * SPDX-License-Identifier: MPL-2.0\n")
	b.WriteString(" */\n\n")

	// Add autogen notice
	b.WriteString("// this file is auto-generated by magic-modules/tools/teamcity-generator, any changes made here will be overwritten\n\n")

	// Add the map
	b.WriteString("var services = mapOf(\n")
	for i, p := range packageNames {
		path := fmt.Sprintf("%s/%s", servicesDir, p)
		var e string
		if i < (len(packageNames) - 1) {
			e = fmt.Sprintf(entryTemplate, p, p, caser.String(p), path)
		} else {
			// Final entry in map doesn't have comma
			e = fmt.Sprintf(lastEntryTemplate, p, p, caser.String(p), path)
		}

		_, err := fmt.Fprint(&b, e)
		if err != nil {
			return "", err
		}

	}
	b.WriteString("\n)\n")

	return b.String(), nil
}
