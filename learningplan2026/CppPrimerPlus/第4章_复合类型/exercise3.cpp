#include "exercises.h"
#include <iostream>
#include <cstring>
using namespace std;

void exercise3()
{
	const int Arsize = 20;
	char first_name[Arsize],last_name[Arsize];
	char name[2*Arsize + 1];
	cout << "Enter your first name: ";
	cin.getline(first_name,Arsize);
	cout << "Enter your last name: ";
	cin.getline(last_name,Arsize);
	strcpy_s(name, last_name);
	strcat_s(name, ",");
	strcat_s(name, first_name);
	cout << "Here's the information in a single string: " << name << endl;
}